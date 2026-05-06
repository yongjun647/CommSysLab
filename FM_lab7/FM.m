%% FM 模擬音頻
clc; clear; close all;

%% 1. 參數設定
mp3_filename = 'music.mp3';
fs_sim = 400e3;      % 模擬取樣率 400 kHz
fc = 100e3;          % 載波頻率 100 kHz ( < fs_sim/2)
FM_Dev = 75e3;       % 頻偏k_f (75 kHz)
Sim_Duration = 10.0; % 模擬長度(秒)

%% 2. 訊號來源(音訊讀取)
if isfile(mp3_filename)
    [y_raw, file_fs] = audioread(mp3_filename);
    y = mean(y_raw, 2); % 轉單聲道
    y = y(1:min(length(y), floor(Sim_Duration * file_fs)));
else
    fprintf('===找不到檔案 ===\n');
end

% 重採樣(Resampling)以確保相容性
t_old = (0:length(y)-1) / file_fs;
t = 0 : 1/fs_sim : t_old(end);
m_t = interp1(t_old, y, t, 'linear')';
m_t(isnan(m_t)) = 0;
m_t = m_t / max(abs(m_t)); % 正規化

%% 3. TX 調變流程(對應流程圖: Integrator -> Multiplier -> Exp -> Mixer)
fprintf('=== [TX] 執行 FM 調變與載波混頻 ===\n');
% [Integrator]
dt = 1/fs_sim;
int_m_t = cumsum(m_t) * dt;
% [Multiplier]
theta_dev = (2*pi* FM_Dev) * int_m_t;
% [exp(j)] 產生複數基頻 IQ
tx_iq_baseband = exp(1j * theta_dev);
% [Mixer] 模擬硬體上變頻與取實部
% 乘上複數載波並取實部,等同於 I*cos - Q*sin
carrier = exp(1j * 2 * pi * fc * t');
s_rf = real(tx_iq_baseband .* carrier);

%% 4. 通道模擬
% 加入高斯白雜訊(模擬空中傳輸)
rx_rf = awgn(s_rf, 30, 'measured');
fprintf('=== [RX] 開始執行硬體架構模擬解調===\n');

%% 5. 射頻前端(對應流程圖: Mixer -> ADC概念)
% [Mixer]正交解調,將RF訊號搬回基頻
lo_i = cos(2*pi*fc*t');    % I路本地震盪
lo_q = -sin(2*pi*fc*t');   % Q路本地震盪
% 混頻並經過低通濾波(移除2fc 成分)
mixer_i = rx_rf .* lo_i;
mixer_q = rx_rf .* lo_q;
[b_analog, a_analog] = butter(4, (fc*1.2)/(fs_sim/2)); % 類比 LPF 模擬
bb_i = filter(b_analog, a_analog, mixer_i) * 2; % 補償振幅
bb_q = filter(b_analog, a_analog, mixer_q) * 2; % 補償振幅
% [+j] 組合為複數基頻 x[n]
x_n = bb_i + 1j * bb_q;

%% 6. 數位解調(對應流程圖: Delay -> Conj -> Multiply -> Angle)
% [Delay & Conj]
x_n_delayed = [0; x_n(1:end-1)];
x_n_conj_delayed = conj(x_n_delayed);
% [Multiply] 相位差分核心
% y[n]=x[n]*x*[n-1]
y_n = x_n .* x_n_conj_delayed;
% [Angle]提取相位差 Delta_Phi
phase_diff = angle(y_n);
% [Scale]換算為頻率(除以2*pi*dt)
demod_signal = phase_diff / (2*pi * dt * FM_Dev);
demod_signal(1) = demod_signal(2); % 修正邊界
% [LPF] 音訊濾波
[b_audio, a_audio] = butter(6, 15000/(fs_sim/2));
m_recovered = filter(b_audio, a_audio, demod_signal);

%% 7. 播放
audio_play = interp1(t, m_recovered, (0:1/file_fs:t(end)), 'linear');
sound(audio_play, file_fs);

%% 8. 繪圖
figure('Color', 'w', 'Position', [100, 100, 800, 600]);
x_zoom = [3.0 3.002]; % 縮放觀察 2ms

subplot(3,1,1);
plot(t, m_t, 'b'); 
title('1. 原始訊息 m(t)');
grid on; ylim([-1.2 1.2]); xlabel('Time (s)');

subplot(3,1,2);
plot(t, rx_rf, 'm'); 
title('2. 接收到的射頻訊號(含載波與雜訊)');
grid on; xlim(x_zoom); xlabel('Time (s)');

subplot(3,1,3);
% plot(t, m_t, 'b', 'LineWidth', 1); hold on;
plot(t, m_recovered, 'r', 'LineWidth', 1.5);
title('3. 解調後訊息');
grid on; ylim([-1.2 1.2]); xlabel('Time (s)');