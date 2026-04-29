%% YTPC1002C01 SDR - FDM WAV Player (1.92MHz 取樣率)
clc; clear; close all;

%% 1. 參數設定
Fs = 1.92e6;              % 取樣率設為 1.92 MHz
Ts = 1/Fs;
Target_Freq_MHz = 433;    % 發射中心頻率 (MHz)
Mod_Index = 0.8;          % AM 調變指數 (0.7~0.9 較理想)
Loop_Duration = 15;       % 總播放時長 (秒)

f_sub1 = 20e3;            % 子載波 1: 20 kHz
f_sub2 = 100e3;           % 子載波 2: 100 kHz

% 替換為 WAV 檔案
wav_file1 = 'music.mp3';
wav_file2 = 'audio2.wav';

%% 2. 音訊讀取與裁切
fprintf('=== SDR FDM WAV 播放器 (1.92MHz 連續發射) 準備中 ===\n');
if ~isfile(wav_file1) || ~isfile(wav_file2)
    error('錯誤: 找不到指定的 WAV 檔案');
end

[y1_full, fs_audio1] = audioread(wav_file1);
[y2_full, fs_audio2] = audioread(wav_file2);

% 轉為單聲道
if size(y1_full, 2) > 1, y1_full = mean(y1_full, 2); end
if size(y2_full, 2) > 1, y2_full = mean(y2_full, 2); end

% 裁切至指定的秒數 (15秒)
samples_15s_1 = floor(Loop_Duration * fs_audio1);
samples_15s_2 = floor(Loop_Duration * fs_audio2);
y1_full = y1_full(1:min(end, samples_15s_1));
y2_full = y2_full(1:min(end, samples_15s_2));

% 若音檔長度不足 15 秒則補零
if length(y1_full) < samples_15s_1, y1_full = [y1_full; zeros(samples_15s_1 - length(y1_full), 1)]; end
if length(y2_full) < samples_15s_2, y2_full = [y2_full; zeros(samples_15s_2 - length(y2_full), 1)]; end

% 強制轉為橫向量 (Row Vector)，符合 YTPC1002C01 API 規範
y1_full = y1_full.';
y2_full = y2_full.';

%% 3. 發射端基頻處理：音訊升頻、AM 調變與 FDM 訊號產生
fprintf('正在進行 1.92MHz 升頻與 FDM 處理 (只需處理一次)...\n');

% 建立音訊時間軸與 SDR 時間軸
data_len = round(Loop_Duration * Fs);
t_sdr = (0:data_len-1) * Ts; % SDR 橫向量時間軸 (1 x 19,200,000)

t_audio1 = (0:samples_15s_1-1) / fs_audio1;
t_audio2 = (0:samples_15s_2-1) / fs_audio2;

% 使用線性內插將音訊升頻至 1.92MHz
m1 = interp1(t_audio1, y1_full, t_sdr, 'linear', 'extrap');
m2 = interp1(t_audio2, y2_full, t_sdr, 'linear', 'extrap');

% --- 【AM 核心數學式】 ---
% 確保音訊正規化
y1_norm = m1 / max(abs(m1));
y2_norm = m2 / max(abs(m2));

% 加上直流偏置並乘上調變指數
s1_am = (1 + Mod_Index * y1_norm);
s2_am = (1 + Mod_Index * y2_norm);

%% 乘上子載波做頻率搬移，兩訊號相加形成 FDM 訊號
s1_cx = s1_am .* exp(1j * 2 * pi * f_sub1 * t_sdr);
s2_cx = s2_am .* exp(1j * 2 * pi * f_sub2 * t_sdr);
tx_complex = s1_cx + s2_cx;

% 歸一化以符合 DAC 範圍 (防止破音)
% 兩首歌合成，最大可能振幅為 2 * (1 + Mod_Index)，保留 0.9 的 Headroom
tx_data = tx_complex / (2 * (1 + Mod_Index)) * 0.9;

%% 4. SDR 發射
fprintf('開始發射 FDM 訊號 (中心頻率 %.1f MHz)...\n', Target_Freq_MHz);
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
    set_TX_power([0 -10]);

    % 無限循環發射！(0 代表無限次數)
    TX_start(tx_data, 0);

    fprintf('------------------------------------------\n');
    fprintf('15秒 WAV FDM 音訊已載入硬體並正在「無限循環播放」中！\n');
    fprintf('  (若要停止發射，請在 Command Window 輸入: TX_close)\n');
    fprintf('------------------------------------------\n');
catch ME
    fprintf('發射失敗: %s\n', ME.message);
end
