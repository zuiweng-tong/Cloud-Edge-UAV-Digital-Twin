% =========================================================
% IEEE 顶刊级 2D 渲染: 宏观城市拓扑与扩散路径 (纯 MATLAB 矢量导出)
% 修改点：将图例整体缩小了约 30%
% =========================================================
clear; clc; close all;

% 1. 检查并加载数据
if ~exist('Urban_Mask_Data.mat', 'file') || ~exist('Data_Macro_3D.mat', 'file')
    error('请先运行 topology.m 初始化环境，然后运行 trajectory.py 生成 Data_Macro_3D.mat。');
end

env = load('Urban_Mask_Data.mat'); 
L = env.L; W = env.W;
H_mask = env.H_mask;
users = env.users; idx = env.idx; cluster_hubs = env.cluster_hubs;
buildings = env.buildings; 
macro_data = load('Data_Macro_3D.mat');

% 2. 构建定制 "浅蓝底" (Light Jet) 色带
c_nodes = [
    0.25, 0.50, 0.95;  % 浅海蓝
    0.00, 0.65, 1.00;  % 亮蓝
    0.00, 1.00, 1.00;  % 青色
    1.00, 1.00, 0.00;  % 黄色
    1.00, 0.00, 0.00;  % 红色
    0.50, 0.00, 0.00   % 暗红
];
node_pos = [1, 38, 90, 166, 217, 256];
light_jet = zeros(256, 3);
for i = 1:3
    light_jet(:,i) = interp1(node_pos, c_nodes(:,i), 1:256, 'linear');
end

% 3. 创建 2D 高清画布
fig = figure('Name', 'Macro-Scale 2D Routing', 'Color', 'w');
set(fig, 'Units', 'centimeters', 'Position', [2, 2, 14, 12]); 
set(fig, 'PaperPositionMode', 'auto', 'InvertHardcopy', 'off');

hold on; box on; 

% 4. 绘制热力背景图
imagesc([0, L], [0, W], H_mask, 'AlphaData', 0.85);
colormap(light_jet);
set(gca, 'YDir', 'normal');

% 5. 设置坐标轴与网格样式
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8);
grid on;
set(gca, 'GridColor', [0.3 0.3 0.3], 'GridAlpha', 0.4, 'GridLineStyle', '--');
xlim([0 L]); ylim([0 W]);
xlabel('X (meters)', 'FontName', 'Times New Roman', 'FontWeight', 'bold');
ylabel('Y (meters)', 'FontName', 'Times New Roman', 'FontWeight', 'bold');

% 6. 绘制轨迹与节点
cluster_colors = [
    0, 0, 0;            % black
    0.55, 0, 0;         % darkred
    0.5, 0, 0.5;        % purple
    0.18, 0.31, 0.31;   % darkslategrey
    0.55, 0.27, 0.07    % saddlebrown
];

unique_clusters = unique(idx(idx > 0));
fields = fieldnames(macro_data);
path_fields = fields(startsWith(fields, 'path_'));

for c = 1:length(unique_clusters)
    c_id = unique_clusters(c);
    c_users = users(idx == c_id, :);
    hub = cluster_hubs(c_id, :);
    curr_path = macro_data.(path_fields{c});
    
    col = cluster_colors(mod(c_id-1, size(cluster_colors,1))+1, :);
    
    % (1) 绘制轨迹
    plot(curr_path(:,1), curr_path(:,2), '-', 'Color', col, 'LineWidth', 1.5);
    
    % (2) 绘制用户节点
    scatter(c_users(:,1), c_users(:,2), 25, 'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    
    % (3) 绘制集散中心
    scatter(hub(1), hub(2), 100, '^', 'MarkerFaceColor', col, ...
        'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
end

% 绘制计算中心 (红色小五角星)
[~, max_b_idx] = max(buildings(:, 5)); 
cloud_x = buildings(max_b_idx, 1);
cloud_y = buildings(max_b_idx, 2);
plot(cloud_x, cloud_y, 'p', 'MarkerSize', 10, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'r');

% 7. 构建定制图例 (关键修改：缩小 30%)
p_lgd_cloud = plot(NaN, NaN, 'p', 'MarkerSize', 7, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'r');
p_lgd_hub = plot(NaN, NaN, '^', 'MarkerSize', 5, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'LineWidth', 1);
p_lgd_user = plot(NaN, NaN, 'o', 'MarkerSize', 3.5, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1);
p_lgd_path = plot(NaN, NaN, '-', 'Color', 'k', 'LineWidth', 1.2);

% 将 FontSize 从 9 降至 6.5
lgd = legend([p_lgd_cloud, p_lgd_hub, p_lgd_user, p_lgd_path], ...
    {'Central Cloud', 'Transit stations', 'User Nodes', 'Flight Path'}, ...
    'Location', 'northeast', 'Box', 'on', 'FontName', 'Times New Roman', 'FontSize', 6.5);

% 通过设置 ItemTokenSize 缩小图标占位的长度
set(lgd, 'EdgeColor', 'k', 'Color', [1 1 1 0.9], 'ItemTokenSize', [12, 6]); 

% 8. 高清矢量导出
drawnow;
exportgraphics(fig, 'Macro_City_Logistics_Final_2D.png', 'Resolution', 600);
exportgraphics(fig, 'Macro_City_Logistics_Final_2D.pdf', 'ContentType', 'vector');
disp('✅ 修改完成：2D 全景图图例已缩小 30%，PDF 矢量图已更新。');