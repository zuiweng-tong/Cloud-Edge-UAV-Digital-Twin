% =========================================================
% IEEE 顶刊级绘图 (修正版 V6): 城市级宏观异构簇分布与扩散模型无障碍路由
% 修正说明: 
% 1. 修复 legend 报错：将 'BackgroundColor' 改为 'Color'
% 2. 移除 legend 不兼容属性 'FaceAlpha'
% 3. 保持云中心无边框红星、小图标、细轨迹 (2.0) 和原版热力图
% =========================================================
clear; clc; close all;

% 检查必要数据文件
if ~exist('Urban_Mask_Data.mat', 'file') || ~exist('Data_Macro.mat', 'file')
    error('请确保已运行 MATLAB 初始化脚本和 Python 算法脚本生成 .mat 数据文件。');
end

load('Urban_Mask_Data.mat', 'H_mask', 'L', 'W', 'users', 'idx', 'cluster_hubs');
macro_data = load('Data_Macro.mat');

% 创建画布 (标准比例)
figure('Name', 'Macro City Routing Fixed', 'Color', 'w', 'Position', [100, 100, 800, 700]);
hold on; box on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 12, 'LineWidth', 1.2, 'TickDir', 'in');

% 1. 绘制背景热力图 - 恢复原版高饱和度
x_vec = linspace(0, L, size(H_mask, 2));
y_vec = linspace(0, W, size(H_mask, 1));
imagesc(x_vec, y_vec, H_mask);
set(gca, 'YDir', 'normal');
colormap('jet');

% 2. 定义深色高对比度调色板
high_contrast_colors = [
    [0.0, 0.0, 0.0]; % 黑色
    [0.7, 0.0, 0.0]; % 深红色
    [0.0, 0.3, 0.0]; % 深绿色
    [0.0, 0.0, 0.6]; % 深蓝色
    [0.4, 0.0, 0.4]; % 深紫色
    [0.5, 0.2, 0.0]; % 棕褐色
];

% 3. 提取并绘制所有簇的轨迹
fields = fieldnames(macro_data);
path_fields = fields(startsWith(fields, 'path_'));

for i = 1:length(path_fields)
    curr_path = macro_data.(path_fields{i});
    col = high_contrast_colors(mod(i-1, size(high_contrast_colors,1))+1, :);
    % 轨迹线宽保持 2.0
    plot(curr_path(:,1), curr_path(:,2), '-', 'Color', col, 'LineWidth', 2.0);
end

% 4. 绘制用户点与中转站 (Hub)
unique_clusters = unique(idx(idx > 0));
for c = 1:length(unique_clusters)
    c_id = unique_clusters(c);
    c_users = users(idx == c_id, :);
    hub = cluster_hubs(c_id, 1:2);
    
    % 绘制用户点
    scatter(c_users(:,1), c_users(:,2), 35, 'w', 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1);
    
    % 绘制中转站 (Hub) - 图标大小 10
    plot(hub(1), hub(2), '^', 'MarkerSize', 10, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
end

% 5. 绘制中心云端计算中心 (Central Cloud) - 无黑色边框
p_cloud_node = plot(L/2, W/2, 'p', 'MarkerSize', 18, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'none');

% 6. 创建图例伪对象 (用于控制图例内的图标外观)
p_cloud_lgd = plot(NaN, NaN, 'p', 'MarkerSize', 10, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'none');
p_hub_lgd = plot(NaN, NaN, '^', 'MarkerSize', 8, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'LineWidth', 1);
p_user_lgd = plot(NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', 'LineWidth', 1);
p_path_lgd = plot(NaN, NaN, 'k-', 'LineWidth', 2.0);

% 7. 设置坐标轴与标签
xlim([0 L]); ylim([0 W]);
xlabel('Horizontal Distance (m)', 'FontWeight', 'bold', 'FontSize', 14);
ylabel('Vertical Distance (m)', 'FontWeight', 'bold', 'FontSize', 14);
% 8. 图例排版 (修正后的参数)
% 使用 'Color' 代替 'BackgroundColor'，移除不支持的 'FaceAlpha'
lgd = legend([p_cloud_lgd, p_hub_lgd, p_user_lgd, p_path_lgd], ...
    {'Central Cloud', 'Logistics Hubs', 'User Terminals', 'Optimized Trajectory'}, ...
    'Location', 'northeast', 'FontSize', 9, 'EdgeColor', 'k', 'Color', 'w');

% 9. 导出高清图像
exportgraphics(gcf, 'Paper_Fig_Macro_Fixed_Final.png', 'Resolution', 600);
disp('✅ 修正后的代码已运行完成，图片已生成: Paper_Fig_Macro_Fixed_Final.png');