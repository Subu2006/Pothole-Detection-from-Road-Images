% =========================================================================
% FUNCTION: acquire_camera_stream.m
% Module: Stage 1B - Live Camera & Dashcam Video Stream Acquisition
% Course: ECE443 Digital Image Processing | Academic Task: CA2
%
% Purpose:
%   Provides a unified, robust, and fail-proof video stream engine supporting:
%     - 'webcam'    : Direct live webcam capture (with hardware fallbacks)
%     - 'video'     : Recorded dashcam road video (.mp4, .avi, .mov) via VideoReader
%     - 'sequence'  : Frame-by-frame image sequence from a directory
%
% Outputs telemetry:
%   - Current RGB frame [H x W x 3]
%   - Status flag (hasFrame: logical)
%   - Telemetry struct: FrameIndex, Timestamp, DeviceName, StreamFPS
% =========================================================================

function varargout = acquire_camera_stream(action, varargin)
    switch lower(action)
        case 'init'
            varargout{1} = init_stream(varargin{:});
        case 'get_frame'
            [varargout{1}, varargout{2}, varargout{3}] = get_next_frame(varargin{:});
        case 'release'
            release_stream(varargin{:});
            varargout{1} = true;
        otherwise
            error('acquire_camera_stream: Unknown action %s. Use init, get_frame, or release.', action);
    end
end

% -------------------------------------------------------------------------
% SUB-FUNCTION: init_stream
% -------------------------------------------------------------------------
function streamObj = init_stream(sourceType, sourcePath, cfg)
    if nargin < 1 || isempty(sourceType)
        sourceType = 'video';
    end
    if nargin < 2, sourcePath = ''; end
    if nargin < 3, cfg = struct(); end

    streamObj = struct();
    streamObj.type       = lower(sourceType);
    streamObj.sourcePath = sourcePath;
    streamObj.isOpen     = false;
    streamObj.frameIndex = 0;
    streamObj.startTime  = tic;
    streamObj.lastTic    = tic;
    streamObj.handle     = [];
    streamObj.fpsCap     = 30;
    streamObj.targetSize = [512, 512];

    if isfield(cfg, 'targetSize'),   streamObj.targetSize = cfg.targetSize; end
    if isfield(cfg, 'streamFpsCap'), streamObj.fpsCap     = cfg.streamFpsCap; end

    switch streamObj.type
        case 'webcam'
            % Attempt hardware webcam connection
            try
                if exist('webcam', 'file') == 2
                    camList = webcamlist();
                    if isempty(camList)
                        warning('acquire_camera_stream: No USB webcam devices found. Falling back to dashcam video.');
                        streamObj.type = 'video';
                    else
                        streamObj.handle = webcam(1);
                        streamObj.isOpen = true;
                        streamObj.deviceName = char(camList{1});
                        fprintf('  [CAMERA] Connected to hardware webcam: %s\n', streamObj.deviceName);
                        return;
                    end
                else
                    warning('acquire_camera_stream: webcam function not installed. Falling back to dashcam simulation.');
                    streamObj.type = 'video';
                end
            catch ME
                fprintf('  [CAMERA NOTICE] Hardware webcam connection failed (%s). Falling back to dashcam.\n', ME.message);
                streamObj.type = 'video';
            end

        case 'video'
            % Video file playback using MATLAB native VideoReader
            if isempty(sourcePath) || ~isfile(sourcePath)
                % Check for default sample video
                rootPath = fileparts(fileparts(mfilename('fullpath')));
                defVideo = fullfile(rootPath, 'dataset', 'demo_dashcam_road.avi');
                if isfile(defVideo)
                    sourcePath = defVideo;
                else
                    % Fall back to sequence of test images
                    streamObj.type = 'sequence';
                    sourcePath = fullfile(rootPath, 'dataset', 'test', 'positive');
                end
            end

            if strcmp(streamObj.type, 'video')
                try
                    streamObj.handle = VideoReader(sourcePath);
                    streamObj.isOpen = true;
                    streamObj.deviceName = sprintf('Dashcam Video [%s]', sourcePath);
                    streamObj.fps = streamObj.handle.FrameRate;
                    fprintf('  [STREAM] Opened road dashcam video: %s (%.1f FPS, %d frames)\n', ...
                        sourcePath, streamObj.handle.FrameRate, streamObj.handle.NumFrames);
                catch ME
                    fprintf('  [STREAM NOTICE] VideoReader failed (%s). Falling back to frame sequence.\n', ME.message);
                    streamObj.type = 'sequence';
                end
            end
    end

    if strcmp(streamObj.type, 'sequence')
        % Sequence directory of images
        if isempty(sourcePath) || ~exist(sourcePath, 'dir')
            rootPath = fileparts(fileparts(mfilename('fullpath')));
            sourcePath = fullfile(rootPath, 'dataset', 'test', 'positive');
        end
        files = dir(fullfile(sourcePath, '*.jpg'));
        if isempty(files)
            files = dir(fullfile(sourcePath, '*.png'));
        end
        streamObj.fileList = files;
        streamObj.folder = sourcePath;
        streamObj.isOpen = ~isempty(files);
        streamObj.deviceName = sprintf('Image Sequence [%d frames]', length(files));
        fprintf('  [STREAM] Initialized road frame sequence (%d frames in %s)\n', ...
            length(files), sourcePath);
    end
end

% -------------------------------------------------------------------------
% SUB-FUNCTION: get_next_frame
% -------------------------------------------------------------------------
function [frameRGB, isFrameValid, telemetry] = get_next_frame(streamObj)
    frameRGB = [];
    isFrameValid = false;
    telemetry = struct('frameIndex', 0, 'fps', 0, 'latency_ms', 0, 'timestamp', datestr(now, 'HH:MM:SS.FFF'));

    if ~streamObj.isOpen
        return;
    end

    tReadStart = tic;

    switch streamObj.type
        case 'webcam'
            try
                rawFrame = snapshot(streamObj.handle);
                isFrameValid = true;
            catch
                isFrameValid = false;
            end

        case 'video'
            try
                if hasFrame(streamObj.handle)
                    rawFrame = readFrame(streamObj.handle);
                    isFrameValid = true;
                else
                    % Loop video stream continuously
                    streamObj.handle.CurrentTime = 0;
                    if hasFrame(streamObj.handle)
                        rawFrame = readFrame(streamObj.handle);
                        isFrameValid = true;
                    end
                end
            catch
                isFrameValid = false;
            end

        case 'sequence'
            N = length(streamObj.fileList);
            if N > 0
                idx = mod(streamObj.frameIndex, N) + 1;
                filePath = fullfile(streamObj.folder, streamObj.fileList(idx).name);
                try
                    rawFrame = imread(filePath);
                    isFrameValid = true;
                catch
                    isFrameValid = false;
                end
            end
    end

    if isFrameValid
        % Resize to standardized working resolution
        if ~isequal(size(rawFrame, [1 2]), streamObj.targetSize)
            frameRGB = imresize(rawFrame, streamObj.targetSize);
        else
            frameRGB = rawFrame;
        end

        % Ensure 3-channel RGB
        if size(frameRGB, 3) == 1
            frameRGB = cat(3, frameRGB, frameRGB, frameRGB);
        end

        streamObj.frameIndex = streamObj.frameIndex + 1;
        tElapsed = toc(tReadStart) * 1000; % ms

        % Empirical instantaneous FPS telemetry
        instantFPS = 1000.0 / max(1.0, tElapsed);
        telemetry.frameIndex  = streamObj.frameIndex;
        telemetry.FrameIndex  = streamObj.frameIndex;
        telemetry.fps         = min(60.0, instantFPS);
        telemetry.StreamFPS   = min(60.0, instantFPS);
        telemetry.latency_ms  = tElapsed;
        telemetry.Latency_ms  = tElapsed;
        telemetry.deviceName  = streamObj.deviceName;
    end
end

% -------------------------------------------------------------------------
% SUB-FUNCTION: release_stream
% -------------------------------------------------------------------------
function release_stream(streamObj)
    if isempty(streamObj) || ~isfield(streamObj, 'isOpen') || ~streamObj.isOpen
        return;
    end
    try
        if strcmp(streamObj.type, 'webcam') && ~isempty(streamObj.handle)
            delete(streamObj.handle);
        end
    catch
    end
end
