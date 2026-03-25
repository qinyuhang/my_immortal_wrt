#!/bin/sh
. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

LOG_OUT "Tip: Start Running Custom Overwrite Scripts..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
CONFIG_FILE="$1"

# ==================== 多订阅合并配置 ====================
# 在这里添加其他订阅的本地路径或URL
# 格式: "订阅名称|路径或URL"
# 支持本地文件路径或http/https订阅链接
ADDITIONAL_SUBSCRIPTIONS=""
# 示例:
# ADDITIONAL_SUBSCRIPTIONS="sub2|/etc/openclash/config/sub2.yaml sub3|https://example.com/sub3.yaml"
# ======================================================

LOG_OUT "Tip: 开始处理多订阅合并..."

# 使用 Ruby 处理配置合并和 Smart Groups 创建
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e "
    require 'open-uri'
    require 'uri'
    
    begin
        Value = YAML.load_file('$CONFIG_FILE');
    rescue Exception => e
        puts '${LOGTIME} Error: Load Main Config Failed,【' + e.message + '】';
        exit 1;
    end;

    begin
        all_proxies = Value['proxies'] || []
        existing_proxy_names = all_proxies.map { |p| p['name'] }.to_set
        
        # 处理额外的订阅
        additional_subs = '$ADDITIONAL_SUBSCRIPTIONS'.strip.split
        additional_subs.each do |sub_info|
            parts = sub_info.split('|', 2)
            next if parts.length < 2
            
            sub_name = parts[0]
            sub_path = parts[1]
            
            begin
                puts '${LOGTIME} Info: 正在加载订阅: ' + sub_name;
                
                # 判断是 URL 还是本地文件
                if sub_path.start_with?('http://', 'https://')
                    # 下载订阅内容
                    sub_content = URI.open(sub_path, 
                        'User-Agent' => 'ClashMetaForAndroid/2.11.7.Meta',
                        :read_timeout => 30
                    ).read
                    sub_config = YAML.load(sub_content)
                else
                    # 读取本地文件
                    sub_config = YAML.load_file(sub_path)
                end
                
                # 合并 proxies，去重
                if sub_config['proxies']
                    sub_config['proxies'].each do |proxy|
                        unless existing_proxy_names.include?(proxy['name'])
                            all_proxies << proxy
                            existing_proxy_names.add(proxy['name'])
                        end
                    end
                    puts '${LOGTIME} Info: ' + sub_name + ' 添加了 ' + sub_config['proxies'].length.to_s + ' 个节点';
                end
                
            rescue Exception => e
                puts '${LOGTIME} Warning: 加载订阅 ' + sub_name + ' 失败,【' + e.message + '】';
            end
        end
        
        # 更新主配置的 proxies
        Value['proxies'] = all_proxies
        
        # ==================== 创建地区 Smart Groups ====================
        all_proxy_names = all_proxies.map { |p| p['name'] }
        
        # 定义地区匹配规则
        region_rules = {
            'HK' => ['香港', 'HK', 'HongKong', 'hongkong', 'Hongkong'],
            'TW' => ['台湾', 'TW'],
            'SG' => ['新加坡', 'SG', 'singapore', 'Singapor'],
            'JP' => ['日本', 'JP', 'Japan'],
            'US' => ['美国', 'US']
        }
        
        exclude_patterns = ['仅海外用户', '游戏']
        
        # 筛选节点
        region_proxies = {}
        new_group_names = region_rules.keys
        
        region_rules.each do |region, patterns|
            matched = all_proxy_names.select do |name|
                matches_region = patterns.any? { |p| name =~ /#{p}/i }
                excluded = exclude_patterns.any? { |ep| name.include?(ep) }
                matches_region && !excluded
            end
            region_proxies[region] = matched.empty? ? ['DIRECT'] : matched
            puts '${LOGTIME} Info: 【' + region + '】Group 匹配 ' + region_proxies[region].length.to_s + ' 个节点';
        end
        
        # 获取原有 proxy-groups
        existing_groups = Value['proxy-groups'] || []
        existing_group_names = existing_groups.map { |g| g['name'] }.to_set
        
        # 创建新的 proxy-groups（只创建不存在的）
        new_groups = []
        region_proxies.each do |region, proxies|
            if existing_group_names.include?(region)
                puts '${LOGTIME} Info: 【' + region + '】Group 已存在，跳过创建';
                next
            end
            new_groups << {
                'name' => region,
                'type' => 'url-test',
                'proxies' => proxies,
                'url' => 'http://www.gstatic.com/generate_204',
                'interval' => 300
            }
        end
        
        # 合并到原有 proxy-groups 前面
        Value['proxy-groups'] = new_groups + existing_groups
        
        # 查找"手动切换" group 并创建"Proxy" group
        manual_switch_group = existing_groups.find { |g| g['name'].include?('手动') || g['name'].include?('手动切换') }
        
        unless existing_group_names.include?('Proxy')
            if manual_switch_group && manual_switch_group['proxies'].is_a?(Array)
                # 找到"手动切换"，创建与其完全一致的 Proxy group
                proxy_group = {
                    'name' => 'Proxy',
                    'type' => manual_switch_group['type'] || 'select',
                    'proxies' => manual_switch_group['proxies'].dup
                }
                
                # 复制其他可能的属性（如果有）
                proxy_group['url'] = manual_switch_group['url'] if manual_switch_group['url']
                proxy_group['interval'] = manual_switch_group['interval'] if manual_switch_group['interval']
                proxy_group['tolerance'] = manual_switch_group['tolerance'] if manual_switch_group['tolerance']
                proxy_group['lazy'] = manual_switch_group['lazy'] if manual_switch_group.key?('lazy')
                proxy_group['disable-udp'] = manual_switch_group['disable-udp'] if manual_switch_group.key?('disable-udp')
                
                # 将 Proxy group 添加到 proxy-groups 列表开头
                existing_groups.unshift(proxy_group)
                existing_group_names.add('Proxy')
                puts '${LOGTIME} Info: 已创建 Proxy group，内容与【' + manual_switch_group['name'] + '】一致';
            else
                # 未找到"手动切换"，创建包含 DIRECT + 地区 groups + 所有节点的 Proxy group
                region_group_names = ['HK', 'TW', 'SG', 'JP', 'US']
                # 筛选出存在的地区 group
                available_region_groups = region_group_names.select { |name| existing_group_names.include?(name) }
                
                # 构建 proxies 列表：DIRECT + 地区 groups + 所有原始节点
                proxy_proxies = ['DIRECT'] + available_region_groups + all_proxy_names
                
                proxy_group = {
                    'name' => 'Proxy',
                    'type' => 'select',
                    'proxies' => proxy_proxies
                }
                
                # 将 Proxy group 添加到 proxy-groups 列表开头
                existing_groups.unshift(proxy_group)
                existing_group_names.add('Proxy')
                puts '${LOGTIME} Info: 未找到"手动切换"，已创建 Proxy group，包含 DIRECT + 地区groups(' + available_region_groups.length.to_s + ') + 所有节点(' + all_proxy_names.length.to_s + ')';
            end
        else
            puts '${LOGTIME} Info: Proxy group 已存在，跳过创建';
        end
        
        # 将新 group 添加到 select 类型的 group 中（只添加新创建的）
        new_groups.reverse.each do |new_group|
            new_group_name = new_group['name']
            existing_groups.each do |group|
                if group['type'] == 'select' && group['proxies'].is_a?(Array)
                    group['proxies'].delete(new_group_name)
                    
                    is_manual_switch = group['name'].include?('手动') || group['name'].include?('手动切换')
                    is_proxy = group['name'] == 'Proxy'
                    
                    if is_manual_switch || is_proxy
                        group['proxies'].unshift(new_group_name)
                        unless group['proxies'].include?('DIRECT')
                            group['proxies'].unshift('DIRECT')
                        end
                    else
                        manual_index = group['proxies'].find_index { |p| p.to_s.include?('手动') }
                        proxy_index = group['proxies'].find_index { |p| p == 'Proxy' }
                        insert_index = [manual_index, proxy_index].compact.min
                        
                        if insert_index
                            group['proxies'].insert(insert_index + 1, new_group_name)
                        else
                            group['proxies'].unshift(new_group_name)
                        end
                    end
                end
            end
        end
        
        puts '${LOGTIME} Info: 配置合并完成，共 ' + all_proxies.length.to_s + ' 个节点';
        
    rescue Exception => e
        puts '${LOGTIME} Error: Merge Config Failed,【' + e.message + '】';
    ensure
        File.open('$CONFIG_FILE','w') {|f| YAML.dump(Value, f)};
    end
" 2>/dev/null >> $LOG_FILE

LOG_OUT "Tip: Custom Overwrite Scripts Finished"
exit 0
