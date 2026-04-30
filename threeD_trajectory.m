% =========================================================
% IEEE 顶刊级 3D 渲染: 修复图窗裁剪与导出适配
% =========================================================
clear; clc; close all;

% 1. 检查并加载数据
if ~exist('Urban_Mask_Data.mat', 'file') || ~exist('Data_Macro_3D.mat', 'file')
    error('请确保已运行 MATLAB 初始化并导出了 buildings，且运行了 Python 生成 Data_Macro_3D.mat。');
end

env = load('Urban_Mask_Data.mat'); 
L = env.L; W = env.W;
users = env.users; idx = env.idx; cluster_hubs = env.cluster_hubs;
buildings = env.buildings;
macro_data = load('Data_Macro_3D.mat');

% 2. 创建符合论文尺寸要求的 3D 画布
% 解决“剪切”问题的关键：显式设置 Units 和 Position
% IEEE 双栏论文单张图建议宽度 8.5-9 cm，单栏建议 12-15 cm
fig = figure('Name', 'Global 3D City Routing', 'Color', 'w');
set(fig, 'Units', 'centimeters', 'Position', [2, 2, 16, 12]); % 设置物理尺寸为 16cm x 12cm

% 解决导出裁剪的核心属性设置
set(fig, 'PaperPositionMode', 'auto'); 
set(fig, 'InvertHardcopy', 'off'); % 保持背景颜色

hold on; box on; grid on; 
view(-42, 38); 

% 优化坐标轴显示
set(gca, 'FontName', 'Times New Roman', 'FontSize', 10, 'LineWidth', 0.8, ...
    'GridColor', [0.5 0.5 0.5], 'GridAlpha', 0.2);

% 3. 绘制科技感半透明 3D 建筑群
bld_color = [0.65, 0.72, 0.80]; 
for b = 1:size(buildings, 1)
    bx = buildings(b,1); by = buildings(b,2);
    bw = buildings(b,3); bl = buildings(b,4); bh = buildings(b,5);
    draw_3d_box(bx, by, bw, bl, bh, bld_color, 0.25); 
end

% 配置 3D 光照（确保导出时不失真）
camlight('headlight'); 
lighting gouraud; 
material([0.6 0.8 0.2 10 0.5]);

% 4. 配色方案
colors = [0 0.447 0.741; 0.85 0.325 0.098; 0.466 0.674 0.188; 0.494 0.184 0.556];

fields = fieldnames(macro_data);
path_fields = fields(startsWith(fields, 'path_'));

% 5. 绘制 3D 航线与投影
for i = 1:length(path_fields)
    curr_path = macro_data.(path_fields{i});
    col = colors(mod(i-1, size(colors,1))+1, :);
    
    % 地面投影 (Z轴设为 0，且 UAV 飞行高度确保高于建筑物)
    plot3(curr_path(:,1), curr_path(:,2), zeros(size(curr_path,1),1), ...
        '--', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.8);
    
    % 主航线
    plot3(curr_path(:,1), curr_path(:,2), curr_path(:,3), ...
        '-', 'Color', col, 'LineWidth', 2.0);
end

% 6. 地面要素
unique_clusters = unique(idx(idx > 0));
for c = 1:length(unique_clusters)
    c_id = unique_clusters(c);
    c_users = users(idx == c_id, :);
    hub = cluster_hubs(c_id, :);
    
    % 用户点
    scatter3(c_users(:,1), c_users(:,2), zeros(size(c_users,1),1), ...
        15, [0.7 0.7 0.7], 'filled', 'MarkerEdgeColor', 'none');
    
    % 传输枢纽 (Transit Hubs)
    plot3(hub(1), hub(2), 0.5, '^', 'MarkerSize', 8, ...
        'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', 'w');
end

% 7. 中心云端
p_cloud = plot3(L/2, W/2, 450, 'p', 'MarkerSize', 15, ...
    'MarkerFaceColor', [0.85 0.325 0.098], 'MarkerEdgeColor', 'w');

% =========================================================
% 8. 标注与图例 (补全版：包含所有物理要素)
% =========================================================
xlim([0 L]); ylim([0 W]); zlim([0 500]);

% --- A. 设置坐标轴标签 ---
xl = xlabel('Horizontal Distance (m)', 'FontName', 'Times New Roman', 'FontWeight', 'bold');
yl = ylabel('Vertical Distance (m)', 'FontName', 'Times New Roman', 'FontWeight', 'bold');
zl = zlabel('Altitude (m)', 'FontName', 'Times New Roman', 'FontWeight', 'bold');

% --- B. 创建图例专用虚拟句柄 (确保图例图标清晰且统一) ---
% 1. 中心云端 (五角星)
p_lgd_cloud = plot3(NaN, NaN, NaN, 'p', 'MarkerSize', 12, ...
    'MarkerFaceColor', [0.85 0.325 0.098], 'MarkerEdgeColor', 'w', 'LineWidth', 1);

% 2. 传输枢纽 (黑色三角形)
p_lgd_hub = plot3(NaN, NaN, NaN, '^', 'MarkerSize', 8, ...
    'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', 'w', 'LineWidth', 1);

% 3. 用户节点 (灰色圆点)
p_lgd_user = plot3(NaN, NaN, NaN, 'o', 'MarkerSize', 5, ...
    'MarkerFaceColor', [0.7 0.7 0.7], 'MarkerEdgeColor', 'none');

% 4. 3D 优化航线 (实线 - 取配色方案中的蓝色作为代表)
p_lgd_path = plot3(NaN, NaN, NaN, '-', 'Color', [0 0.447 0.741], 'LineWidth', 2);


% --- C. 生成图例 ---
% 按逻辑顺序排列：基础设施 -> 节点 -> 结果
[lgd, ~] = legend([p_lgd_cloud, p_lgd_hub, p_lgd_user, p_lgd_path], ...
    {'Central Cloud', 'Transit Hubs', 'User Nodes', '3D Flight Path'}, ...
    'Location', 'northeast', 'Box', 'on', 'FontName', 'Times New Roman', 'FontSize', 9);
set(lgd, 'EdgeColor', [0.8 0.8 0.8], 'LineWidth', 0.5); % 微调图例边框，使其不那么突兀

% --- D. 核心修复：强制拉近坐标轴标签 ---
drawnow; % 必须先渲染
set(xl, 'Units', 'normalized');
set(yl, 'Units', 'normalized');
set(zl, 'Units', 'normalized');

% 调整 Vertical Distance 标签位置 (Position 是 [x, y, z])
% 增加第一个参数使标签向坐标轴靠拢
yl.Position(1) = yl.Position(1) + 0.08; 
yl.Position(2) = yl.Position(2) + 0.05; 

% 调整 Horizontal Distance 标签位置
xl.Position(2) = xl.Position(2) + 0.05;

% --- E. 高清导出 ---
exportgraphics(fig, 'UAV_3D_Trajectory_Complete.png', 'Resolution', 600);
disp('✅ 图例已补全，高清图片已导出。');

% --- 辅助函数 ---
function draw_3d_box(cx, cy, w, l, h, col, alpha)
    x = cx + [-w/2, w/2, w/2, -w/2, -w/2, w/2, w/2, -w/2];
    y = cy + [-l/2, -l/2, l/2, l/2, -l/2, -l/2, l/2, l/2];
    z = [0, 0, 0, 0, h, h, h, h];
    f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 5 6 7 8; 1 2 3 4];
    patch('Vertices', [x' y' z'], 'Faces', f, 'FaceColor', col, 'FaceAlpha', alpha, ...
        'EdgeColor', col*0.8, 'LineWidth', 0.1);
end