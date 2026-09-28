function plan = placidoGuidedPlan(irSeconds, solidSeconds, halfSeconds, blocks)
% Nominal host-command schedule, shared by USB camera and smartphone paths.
% White OFF does not establish infrared illumination or physical LED state.
arguments
    irSeconds (1,1) double {mustBePositive} = 3
    solidSeconds (1,1) double {mustBePositive} = 5
    halfSeconds (1,1) double {mustBePositive} = 0.5
    blocks (1,1) double {mustBeInteger, mustBePositive} = 5
end
times = irSeconds;
events = {'solid_placido_on'};
commands = {'A'};
for k = 1:blocks
    t = irSeconds + solidSeconds + (k-1)*2*halfSeconds;
    times = [times; t; t+halfSeconds]; %#ok<AGROW>
    events = [events; {sprintf('block_%d_placido_off', k); ...
        sprintf('block_%d_placido_on', k)}]; %#ok<AGROW>
    commands = [commands; {'O'; 'A'}]; %#ok<AGROW>
end
times(end+1,1) = irSeconds + solidSeconds + blocks*2*halfSeconds;
events{end+1,1} = 'record_end_placido_off';
commands{end+1,1} = 'O';
plan = table(events, times, commands, 'VariableNames', ...
    {'Event', 'PlannedTimeSeconds', 'ArduinoCommand'});
end
