% dataset/create_demo_dashcam.m
filePath = which('create_demo_dashcam');
if isempty(filePath)
    rootPath = pwd;
else
    rootPath = fileparts(fileparts(filePath));
end
addpath(rootPath);
addpath(fullfile(rootPath, 'src'));
cfg = config();

outVideoPath = fullfile(rootPath, 'dataset', 'demo_dashcam_road.avi');
fprintf('Creating realistic demo dashcam video: %s\n', outVideoPath);

v = VideoWriter(outVideoPath, 'Motion JPEG AVI');
v.FrameRate = 15;
v.Quality = 90;
open(v);

% Source road frames
cleanRoad = imread(fullfile(rootPath, 'dataset', 'test', 'negative', 'real_normal_test_01.jpg'));
cleanRoad = imresize(cleanRoad, [512, 512]);

potholeRoad1 = imread(fullfile(rootPath, 'dataset', 'test', 'positive', 'real_pothole_test_01.jpg'));
potholeRoad1 = imresize(potholeRoad1, [512, 512]);

potholeRoad2 = imread(fullfile(rootPath, 'dataset', 'test', 'positive', 'images.jpg'));
potholeRoad2 = imresize(potholeRoad2, [512, 512]);

% Generate 60 frames (4 seconds at 15 FPS)
% Frames 1-15: Clean road with subtle camera vibration
for f = 1:15
    dx = round(1.5 * sin(f * 0.8));
    dy = round(1.0 * cos(f * 0.6));
    shifted = imtranslate(cleanRoad, [dx, dy], 'FillValues', 128);
    writeVideo(v, shifted);
end

% Frames 16-30: Approaching pothole 1 (cross-fade & perspective forward motion)
for f = 1:15
    alpha = (f - 1) / 14;
    blended = uint8((1 - alpha) * double(cleanRoad) + alpha * double(potholeRoad1));
    writeVideo(v, blended);
end

% Frames 31-45: Pothole 1 in focus with slight vibration
for f = 1:15
    dx = round(2.0 * sin(f * 1.1));
    dy = round(1.5 * cos(f * 0.9));
    shifted = imtranslate(potholeRoad1, [dx, dy], 'FillValues', 128);
    writeVideo(v, shifted);
end

% Frames 46-60: Transition to puddle road
for f = 1:15
    alpha = (f - 1) / 14;
    blended = uint8((1 - alpha) * double(potholeRoad1) + alpha * double(potholeRoad2));
    writeVideo(v, blended);
end

close(v);
fprintf('Successfully generated %s (60 frames, 15 FPS)!\n', outVideoPath);
