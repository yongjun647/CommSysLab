%% SDR MP3 Player (DSB-SC 零中頻直驅版 - 使用 SDR 射頻當載波)
% 功能：讀取 MP3 -> 裁切 -> 重採樣去直流 -> 零中頻調變 -> 無限循環發射
clc; clear; close all;

%% --- 1. 讀取音訊檔案與參數設定 ---
fprintf('=== MP3 DSB-SC 音樂電台 (Zero-IF) ===\n');
mp3_filename = 'music.mp3';

% 檢查檔案是否存在
if ~isfile(mp3_filename)
    error('錯誤：找不到檔案 %s', mp3_filename);
end

% 讀取音訊檔案
[y, fs_audio] = audioread(mp3_filename);

% 若為雙聲道立體聲，取平均轉成單聲道 (Mono)
if size(y, 2) > 1
    y = mean(y, 2);
end

% 根據 Loop_Duration 計算取樣點數並裁切
Loop_Duration = 20; % 設定為 20 秒以確保不超過硬體記憶體極限
samples_Duration = floor(Loop_Duration * fs_audio);
y = y(1:min(end, samples_Duration));

fprintf('成功讀取音訊，裁切長度：%.2f 秒\n', length(y)/fs_audio);

%% --- 2. 參數與重採樣 ---
fs = 960e3;             % 通訊採樣率：1.92 MHz (配合 SDR 硬體)
Target_Freq_MHz = 433;  % SDR 硬體中心頻率 (RF)

fprintf('正在進行重採樣至 %.2f MHz... (請稍候)\n', fs/1e6);

% --- TX 修改部分 ---
% 將音訊提升到通訊採樣率
mt = resample(y, fs, fs_audio).';

% 移除原始音樂的直流，並縮小振幅預留空間給 DC
mt = mt - mean(mt);
mt = (mt / max(abs(mt))) * 0.8; 

% 【關鍵修改】加入 DC 偏壓 (Pilot Tone)
% 這會在頻譜正中央產生一根載波能量
DC_offset = 0.5; 
tx_data = complex(mt + DC_offset, 0);

%% --- 3. DSB-SC 調變 (零中頻 Zero-IF) ---
fprintf('正在進行基頻 IQ 映射...\n');

% 不再使用 cos 產生數位載波。
% 直接將實數音樂放進 I 通道，Q 通道填 0。
% SDR 硬體會自動將這個 I 通道乘上 433 MHz 的 cos 載波。
%tx_data = complex(mt, 0);

%% --- 4. 呼叫 SDR 硬體發射 ---
fprintf('準備發射 (中心頻率 %.1f MHz)...\n', Target_Freq_MHz);

% 安全防呆：檢查是否超過硬體極限 (80,000,000 samples)
if length(tx_data) > 8e7
    error('錯誤：資料量超過硬體極限！請縮短 Loop_Duration。');
end

try
    % 1. 設定中心頻率
    LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);

    % 2. 設定發射功率
    set_TX_power([0 -10]);

    % 3. 無限循環發射 (第二個參數 0 代表無限重複)
    TX(tx_data, 0);

    fprintf('--------------------------------------------------\n');
    fprintf('? DSB-SC 播放中！音樂正在空中無限循環。\n');
    fprintf('   (請觀察頻譜儀：以 %.1f MHz 為中心對稱，且中央無突起載波)\n', Target_Freq_MHz);
    fprintf('   (若要停止，請在下方指令列輸入: TX_close)\n');
    fprintf('--------------------------------------------------\n');

    % 畫出發射前的基頻頻譜供確認
    figure('Name', 'Baseband Spectrum', 'Color', 'w');
    L = length(tx_data);
    f_axis = fs*(-L/2:L/2-1)/L;
    fft_data = fftshift(fft(tx_data));
    plot(f_axis/1000, 20*log10(abs(fft_data)/L)); % 改用 dB 顯示較清晰
    title('送入 SDR 前的基頻頻譜 (Zero-IF)');
    xlabel('頻率 (kHz)'); ylabel('Magnitude (dB)'); grid on;
    xline(0, '--r', 'DC (SDR 載波映射位置)');

catch ME
    fprintf('發射失敗: %s\n', ME.message);
end