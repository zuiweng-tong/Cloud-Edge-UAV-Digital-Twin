% =========================================================
% IEEE 顶刊级绘图: 单点 TDOA 报警与大模型边缘避险重绘
% =========================================================
clear; clc; close all;
load('Urban_Mask_Data.mat', 'H_mask', 'L', 'W');
load('Data_Crisis.mat');

figure('Name', 'Crisis Evasive Maneuver', 'Color', 'w', 'Position', [150, 150, 700, 650]);
hold on; box on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 12, 'LineWidth', 1.2, 'TickDir', 'in');

% 绘制背景热力图
x_vec = linspace(0, L, size(H_mask, 2));
y_vec = linspace(0, W, size(H_mask, 1));
imagesc(x_vec, y_vec, H_mask);
set(gca, 'YDir', 'normal');
colormap('jet');
alpha 0.85; % 透明度

% 绘制受骗轨迹 (致命路线)
p1 = plot(fatal_traj(:,1), fatal_traj(:,2), '--', 'Color', [0.8, 0.8, 0.8], 'LineWidth', 4, 'DisplayName', 'Fatal Command (Spoofed Path)');

% 绘制求生轨迹 (边缘孪生重绘)
p2 = plot(edge_traj(:,1), edge_traj(:,2), '-', 'Color', [1 0.5 0], 'LineWidth', 4, 'DisplayName', 'Emergency Escape (Edge DT)');

% 绘制起点和终点
p3 = plot(crisis_pt(1), crisis_pt(2), 'p', 'MarkerSize', 20, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'w', 'LineWidth', 1.5, 'DisplayName', 'TDOA Alarm Trigger (C_{flag} = 1)');
p4 = plot(target_pt(1), target_pt(2), 'o', 'MarkerSize', 12, 'MarkerFaceColor', 'b', 'MarkerEdgeColor', 'w', 'LineWidth', 1.5, 'DisplayName', 'Target / Safe Anchor');

% 动态缩放镜头
margin = 400;
min_x = max(0, min([crisis_pt(1), target_pt(1), min(edge_traj(:,1))]) - margin);
max_x = min(L, max([crisis_pt(1), target_pt(1), max(edge_traj(:,1))]) + margin);
min_y = max(0, min([crisis_pt(2), target_pt(2), min(edge_traj(:,2))]) - margin);
max_y = min(W, max([crisis_pt(2), target_pt(2), max(edge_traj(:,2))]) + margin);

span_x = max_x - min_x; span_y = max_y - min_y;
max_span = max(span_x, span_y);
cx = (min_x + max_x)/2; cy = (min_y + max_y)/2;
xlim([cx - max_span/2, cx + max_span/2]);
ylim([cy - max_span/2, cy + max_span/2]);

xlabel('X (meters)', 'FontWeight', 'bold', 'FontSize', 13);
ylabel('Y (meters)', 'FontWeight', 'bold', 'FontSize', 13);
title('Crisis Response: TDOA Alarm & Edge DT Evasive Maneuver', 'FontWeight', 'bold', 'FontSize', 14);

% 图例设置 (支持 Latex)
lgd = legend([p1, p2, p3, p4], 'Location', 'northeast');
set(lgd, 'FontSize', 11, 'EdgeColor', 'k');

exportgraphics(gcf, 'Paper_Fig_Crisis.png', 'Resolution', 600);
disp('✅ 顶刊微观避险图已生成: Paper_Fig_Crisis.png');