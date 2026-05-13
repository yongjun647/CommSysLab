%% [TX] FM 實作發射機
clc; clear; close all;

%% 1. TX參數設定
mp3_filename = 'Music.mp3';
Target_Freq  = 433;           % 中心頻率 (MHz)
SR_hw        = 1.92e6;        % 硬體物理取樣率 (ADC/DAC 頻率)
fs_proc      = 192e3;         % 數位處理取樣率
FM_Dev       = 75e3;          % 頻偏 k_f
tx_power     = -10;           % 發射功率
tx_time      = 10;            % 預計發射 10 秒

%% 2. 訊號預處理
fprintf('=== [TX] 啟動數位基頻處理 ===\n');
[y, fs_file] = audioread(mp3_filename);
y = y(:, 1); % 取單聲道
len_samples = floor(tx_time * fs_file);
if length(y) > len_samples, y = y(1:len_samples); end

%% 3. 數位處理 (Digital Domain: m[n])
% [Input m[n]] 重採樣並正規化
m_n = resample(y, fs_proc, fs_file);
m_n = m_n / max(abs(m_n));

% [Integrator] 離散累加近似積分 (Σ m[k]*dt)
dt_proc = 1/fs_proc;
int_m_n = cumsum(m_n) * dt_proc;

% [Multiplier] 產生相位 θ[n] = 2 * pi * k_f * Σm*dt
theta_n = (2 * pi * FM_Dev) * int_m_n;

% [e^j()] 產生數位複數基頻 I[n] + jQ[n]
iq_base_n = exp(1j * theta_n);

% [模擬 DAC]
% 透過 10 倍重採樣，讓數位訊號準備送入 SDR 物理層
tx_iq_dac = resample(iq_base_n, 10, 1);
tx_data = double(tx_iq_dac(:).') * 0.5;%% 3. 數位處理 (Digital Domain: m[n])
% [Input m[n]] 重採樣並正規化
m_n = resample(y, fs_proc, fs_file);
m_n = m_n / max(abs(m_n));

% [Integrator] 離散累加近似積分 (Σ m[k]*dt)
dt_proc = 1/fs_proc;
int_m_n = cumsum(m_n) * dt_proc;

% [Multiplier] 產生相位 θ[n] = 2 * pi * k_f * Σm*dt
theta_n = (2 * pi * FM_Dev) * int_m_n;

% [e^j()] 產生數位複數基頻 I[n] + jQ[n]
iq_base_n = exp(1j * theta_n);

% [模擬 DAC]
% 透過 10 倍重採樣，讓數位訊號準備送入 SDR 物理層
tx_iq_dac = resample(iq_base_n, 10, 1);
tx_data = double(tx_iq_dac(:).') * 0.5;

%% 4. 硬體發射 (Analog Domain: s(t))
fprintf('正在經由 DAC 與 Mixer 發射射頻訊號...\n');
try
    LO_CHANGE(0, Target_Freq, Target_Freq);
    set_TX_power([0 tx_power]);
    TX_start(tx_data, 0); % 循環發射
    fprintf('★ TX 發射中 (頻率: %d MHz)\n', Target_Freq);
catch ME
    error('TX 硬體錯誤: %s', ME.message);
end