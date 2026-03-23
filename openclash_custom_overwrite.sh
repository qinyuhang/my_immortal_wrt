#!/bin/sh
. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

# This script is called by /etc/init.d/openclash
# Add your custom overwrite scripts here, they will be take effict after the OpenClash own srcipts

LOG_OUT "Tip: Start Running Custom Overwrite Scripts..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
#Config Path
CONFIG_FILE="$1"

# ==================== 添加自定义 URL-Test Proxy Groups（含节点筛选）====================
LOG_OUT "Tip: 添加自定义 URL-Test Proxy Groups..."

# 使用 Ruby 脚本处理节点筛选和 Group 创建
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e "
    begin
        Value = YAML.load_file('$CONFIG_FILE');
    rescue Exception => e
        puts '${LOGTIME} Error: Load File Failed,【' + e.message + '】';
        exit 1;
    end;

    begin
        # 获取所有代理节点名称
        all_proxies = Value['proxies']&.map { |p| p['name'] } || []
        
        # 定义地区匹配规则: 名称 -> [正则匹配模式]
        region_rules = {
            'HK' => ['香港', 'HK', 'HongKong', 'hongkong', 'Hongkong'],
            'TW' => ['台湾', 'TW'],
            'SG' => ['新加坡', 'SG', 'singapore', 'Singapor'],
            'JP' => ['日本', 'JP', 'Japan'],
            'US' => ['美国', 'US']
        }
        
        # 排除规则：排除包含这些关键词的节点
        exclude_patterns = ['仅海外用户', '游戏']
        
        # 为每个地区创建筛选后的节点列表
        region_proxies = {}
        new_group_names = region_rules.keys
        
        region_rules.each do |region, patterns|
            matched = all_proxies.select do |name|
                # 检查是否匹配地区模式（不区分大小写）
                matches_region = patterns.any? { |p| name =~ /#{p}/i }
                # 检查是否包含排除关键词
                excluded = exclude_patterns.any? { |ep| name.include?(ep) }
                matches_region && !excluded
            end
            region_proxies[region] = matched.empty? ? ['DIRECT'] : matched
            puts '${LOGTIME} Info: 【' + region + '】Group 添加 ' + region_proxies[region].length.to_s + ' 个节点';
        end
        
        # 创建 proxy-groups
        new_groups = []
        region_proxies.each do |region, proxies|
            new_groups << {
                'name' => region,
                'type' => 'url-test',
                'proxies' => proxies,
                'url' => 'http://www.gstatic.com/generate_204',
                'interval' => 300
            }
        end
        
        # 将新 groups 插入到原有 proxy-groups 前面
        existing_groups = Value['proxy-groups'] || []
        Value['proxy-groups'] = new_groups + existing_groups
        
        # 将新 group 添加到所有 select 类型的 group 中
        # 对于"手动切换"，放到最前面
        # 对于其他 selector，放到"手动切换"之后（避免改变默认选中）
        new_group_names.reverse.each do |new_group|
            existing_groups.each do |group|
                if group['type'] == 'select' && group['proxies'].is_a?(Array)
                    # 删除已存在的（避免重复）
                    group['proxies'].delete(new_group)
                    
                    # 判断是否是"手动切换"（通常是第一个 select group 或名称包含手动）
                    is_manual_switch = group['name'].include?('手动') || group['name'].include?('手动切换')
                    
                    if is_manual_switch
                        # 手动切换：插入到最前面
                        group['proxies'].unshift(new_group)
                    else
                        # 其他 selector：找到"手动切换"的位置，插入到其后
                        manual_index = group['proxies'].find_index { |p| p.to_s.include?('手动') }
                        if manual_index
                            group['proxies'].insert(manual_index + 1, new_group)
                        else
                            # 如果没找到手动切换，还是放到最前面（但这种情况应该很少）
                            group['proxies'].unshift(new_group)
                        end
                    end
                end
            end
        end
        
        puts '${LOGTIME} Info: 已将新 Groups 添加到策略组中（手动切换在最前，其他在手动切换后）';
        
    rescue Exception => e
        puts '${LOGTIME} Error: Create Smart Groups Failed,【' + e.message + '】';
    ensure
        File.open('$CONFIG_FILE','w') {|f| YAML.dump(Value, f)};
    end
" 2>/dev/null >> $LOG_FILE

LOG_OUT "Tip: URL-Test Proxy Groups 添加完成"
# ======================================================================

exit 0
