% =========================================================
% IEEE 顶刊级绘图: UAV生存率曲线 (带阴影蒙特卡洛置信区间)
% 特性: 完美的线条对比、左下角防遮挡图例、学术字体排版
% =========================================================
clear; clc; close all;

% 确保数据存在
if ~exist('Data_Survival.mat', 'file')
    error('未找到 Data_Survival.mat，请先运行 Python 仿真脚本！');
end
load('Data_Survival.mat');

% 创建标准尺寸的白底画布
figure('Name', 'Robustness Evaluation', 'Color', 'w', 'Position', [100, 100, 750, 550]);
hold on; grid on; box on;

% 统一设置全局学术字体和刻度朝内
set(gca, 'FontName', 'Times New Roman', 'FontSize', 13, 'LineWidth', 1.5, 'TickDir', 'in');
set(gca, 'GridAlpha', 0.5, 'GridLineStyle', '--'); % 调整网格线透明度和样式

% 提取数据 (确保转为双精度以便绘图)
x = double(x_vals(1,:));
c_mean = double(cloud_mean(1,:)); c_std = double(cloud_std(1,:));
cr_mean = double(crypto_mean(1,:)); cr_std = double(crypto_std(1,:));
p_mean = double(proposed_mean(1,:)); p_std = double(proposed_std(1,:));

% 定义 IEEE 经典高对比度配色 (红、蓝、绿)
c_red = [0.839, 0.152, 0.156];
c_blue = [0.121, 0.466, 0.705];
c_green = [0.172, 0.627, 0.172];

% 辅助函数内部实现：同时绘制半透明误差阴影带和主线
% 1. 绘制阴影带 (置于底层)
fill([x, fliplr(x)], [c_mean-c_std, fliplr(c_mean+c_std)], c_red, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
fill([x, fliplr(x)], [cr_mean-cr_std, fliplr(cr_mean+cr_std)], c_blue, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
fill([x, fliplr(x)], [p_mean-p_std, fliplr(p_mean+p_std)], c_green, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

% 2. 绘制主线条
p1 = plot(x, c_mean, 's--', 'Color', c_red, 'LineWidth', 2.5, 'MarkerSize', 10, 'MarkerFaceColor', c_red);
p2 = plot(x, cr_mean, '^-.', 'Color', c_blue, 'LineWidth', 2.5, 'MarkerSize', 10, 'MarkerFaceColor', c_blue);
p3 = plot(x, p_mean, 'o-', 'Color', c_green, 'LineWidth', 2.5, 'MarkerSize', 10, 'MarkerFaceColor', c_green);

% 设置坐标轴与标签
xlabel('ADS-B Spoofing Attack Intensity (%)', 'FontWeight', 'bold', 'FontSize', 15);
ylabel('UAV Survival Rate (%)', 'FontWeight', 'bold', 'FontSize', 15);


% 精确控制坐标轴范围和刻度
xlim([0 50]);
ylim([0 105]); 
xticks(0:10:50);
yticks(0:20:100);

% 图例美化与位置调整 (移至左下角，避免遮挡曲线)
lgd = legend([p1, p2, p3], ...
    {'Baseline: Cloud-Only (No Edge DT)', ...
     'Baseline: Crypto-Auth Only', ...
     'Proposed: Cloud-Edge DT (TDOA + Diffusion)'}, ...
    'Location', 'southwest', 'NumColumns', 1);
set(lgd, 'Interpreter', 'none', 'FontSize', 12, 'EdgeColor', 'k', 'LineWidth', 1.2, 'Color', 'w');

% 导出为超清 600dpi 图片
exportgraphics(gcf, 'Paper_Fig_Survival_Rate_Final.png', 'Resolution', 600);
disp('✅ 完美的顶刊生存率曲线图已生成: Paper_Fig_Survival_Rate_Final.png');