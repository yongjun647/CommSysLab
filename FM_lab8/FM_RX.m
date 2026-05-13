%% [RX] FM 實作接收機
clc; clear; close all;

%% 1. RX參數設定 (必須與 TX 一致)
Target_Freq = 433;      % 中心頻率 (MHz)
SR_hw       = 1.92e6;   % 物理取樣率
Block_Time  = 10.0;     % 每次處理 10 秒數據
Audio_Fs    = 48000;    % 音頻取樣率
FM_Dev      = 75e3;     % 頻偏 k_f
rx_power    = -10;      % 接收增益

%% 2. 硬體初始化
fprintf('=== [RX] 啟動射頻接收前端 ===\n');
try
    LO_CHANGE(0, Target_Freq, Target_Freq);
    set_RX_Ref_Level_ELSDR([0 rx_power]);
    pause(1);
catch ME
    error('RX 硬體錯誤: %s', ME.message);
end

%% 3. 解調
fprintf('開始執行相位差分數位解調...\n');

% --- [Input: ADC 採樣輸出 x[n]] ---
rx_n = RX(1, round(Block_Time * SR_hw));
rx_n = double(rx_n(:));
rx_n = rx_n - mean(rx_n); % 數位去直流

% --- [帶通濾波器，只保留中間 200kHz 帶寬] ---
BW_filter = 200e3; % 設定濾波頻寬
[b_rf, a_rf] = butter(4, (BW_filter/2)/(SR_hw/2));
rx_n = filter(b_rf, a_rf, rx_n); % 濾除主訊號以外的雜散點

% [Delay] 取得過去的點 x[n-1]
x_n_delayed = [0; rx_n(1:end-1)];

% [Multiply] 複數乘法 y[n] = x[n] * x*[n-1]
y_n = rx_n .* conj(x_n_delayed);

% [Angle] 提取相位差
phase_diff = angle(y_n);

% [Scaling] 換算為頻率並除以 dt
% 頻率還原公式: m[n] = (Δ/ dt) / (2 * pi * k_f)
dt_hw = 1/SR_hw;
m_recovered = phase_diff / (2 * pi * FM_Dev * dt_hw);

% [LPF] 音訊低通濾波 (15kHz)
[b_lpf, a_lpf] = butter(6, 15000/(SR_hw/2));
m_filtered = filter(b_lpf, a_lpf, m_recovered);

% 音頻播放
audio_out = resample(m_filtered, Audio_Fs, SR_hw);

fprintf('播放解調音訊中...\n');
soundsc(audio_out, Audio_Fs);

%% 4. 繪製解調後音訊時域圖
t_axis = (0:length(audio_out)-1) / Audio_Fs; % 建立時間軸 (秒)

figure('Color', 'w', 'Name', 'Post-Demodulation Audio Waveform');
plot(t_axis, audio_out, 'Color', [0 0.4470 0.7410]);

grid on;
title('Demodulated Audio Waveform (Time Domain)');
xlabel('Time (seconds)');
ylabel('Amplitude');

% xlim([0 0.1]);
ylim([-1.1 1.1]);