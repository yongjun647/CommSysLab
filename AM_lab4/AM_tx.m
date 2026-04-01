%% SDR MP3 Player - TX AM
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;              % 軟體基頻取樣率
Target_Freq_MHz = 433;   % 發射頻率
Mod_Index = 0.8;
mp3_filename = 'music.mp3';
Loop_Duration = 10;

%% 2. 音頻讀取
fprintf('=== YTTEK SDR AM 電台發射端 ===\n');
if ~isfile(mp3_filename)
    error('錯誤：找不到檔案 %s', mp3_filename);
end

[y, file_fs] = audioread(mp3_filename);
if size(y, 2) > 1, y = mean(y, 2); end

% 轉置音訊確保後續處理皆為 1 個 row 的橫向量
if size(y, 1) > 1, y = y.'; end

samples_10s = floor(Loop_Duration * file_fs);
y = y(1, 1:min(end, samples_10s));

%% 3. 訊號處理 (AM 調變)
fprintf('正在進行 AM 調變處理...\n');
fs_proc = 192e3;
y_resamp = resample(y, fs_proc, file_fs);

% 1. 正規化
y_norm = y_resamp / max(abs(y_resamp));

% 2. 加上直流偏置並乘上調變指數 (產生純實數的 1 row x N column 陣列)
iq_base = (1 + Mod_Index * y_norm);

% 3. Up-sampling
upsample_ratio = floor(SR / fs_proc);
tx_data = rectpulse(iq_base, upsample_ratio);

tx_data = tx_data / (1 + Mod_Index) * 0.9;

tx_data = complex(tx_data, 0);

%% 4. 發射
fprintf('開始發射 AM 訊號 (頻率 %.1f MHz)...\n', Target_Freq_MHz);
try
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
    set_TX_power([0 -10]);
    
    % 無限循環發射
    TX_start(tx_data, 0);
    
    fprintf('------------------------------------\n');
    fprintf('AM 播放中！\n');
    fprintf(' (若要停止，請輸入：TX_close)\n');
    fprintf('------------------------------------\n');
catch ME
    fprintf('發射失敗：%s\n', ME.message);
end