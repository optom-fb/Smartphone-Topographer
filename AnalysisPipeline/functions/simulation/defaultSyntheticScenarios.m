function scenarios = defaultSyntheticScenarios()
%DEFAULTSYNTHETICSCENARIOS Return representative research test surfaces.
%   SCENARIOS = DEFAULTSYNTHETICSCENARIOS() returns a 43 D sphere; low and
%   moderate WTR, ATR, and oblique regular astigmatism; and early, moderate,
%   and severe keratoconus-like mathematical surfaces. These engineering
%   labels are not clinical diagnoses or validated clinical grades.
%
%   Radii use the keratometric-index convention K = 337.5 / radius(mm).
%   AxisDeg denotes the FLAT meridian: WTR = 0 deg, ATR = 90 deg, and the
%   selected oblique case = 45 deg. ConeCenterMm uses physical [x y]
%   coordinates, with y positive superior.

base = struct( ...
    'Name', "", ...
    'SurfaceClass', "", ...
    'Severity', "", ...
    'AstigmatismOrientation', "none", ...
    'RflatMm', 337.5 / 43.0, ...
    'RsteepMm', 337.5 / 43.0, ...
    'AxisDeg', 0, ...
    'Q', -0.25, ...
    'ConeAmplitudeMm', 0, ...
    'ConeCenterMm', [0, 0], ...
    'ConeSigmaMm', 1.5, ...
    'BrokenArcFraction', 0, ...
    'GlareStrength', 0, ...
    'NoiseSigma', 0.004, ...
    'BlurSigma', 0.40);

scenarios = repmat(base, 1, 10);

scenarios(1).Name = "sphere_43D";
scenarios(1).SurfaceClass = "sphere";
scenarios(1).Severity = "reference";
% A sphere is the Q = 0 conic. Keep the cornea-like Q = -0.25 default for
% regular astigmatism, but do not let the named sphere inherit it.
scenarios(1).Q = 0;

scenarios(2) = regularAstigmatism(base, ...
    "astigmatism_wtr_low", "low", "WTR", 1.0, 0);
scenarios(3) = regularAstigmatism(base, ...
    "astigmatism_wtr_moderate", "moderate", "WTR", 2.5, 0);
scenarios(4) = regularAstigmatism(base, ...
    "astigmatism_atr_low", "low", "ATR", 1.0, 90);
scenarios(5) = regularAstigmatism(base, ...
    "astigmatism_atr_moderate", "moderate", "ATR", 2.5, 90);
scenarios(6) = regularAstigmatism(base, ...
    "astigmatism_oblique_low", "low", "oblique", 1.0, 45);
scenarios(7) = regularAstigmatism(base, ...
    "astigmatism_oblique_moderate", "moderate", "oblique", 2.5, 45);

scenarios(8).Name = "keratoconus_early";
scenarios(8).SurfaceClass = "keratoconus-like";
scenarios(8).Severity = "early";
scenarios(8).RflatMm = 7.70;
scenarios(8).RsteepMm = 7.35;
scenarios(8).AxisDeg = 35;
scenarios(8).Q = -0.40;
scenarios(8).ConeAmplitudeMm = 0.05;
scenarios(8).ConeCenterMm = [0.35, -0.45];
scenarios(8).ConeSigmaMm = 1.55;

scenarios(9).Name = "keratoconus_moderate";
scenarios(9).SurfaceClass = "keratoconus-like";
scenarios(9).Severity = "moderate";
scenarios(9).RflatMm = 7.40;
scenarios(9).RsteepMm = 6.90;
scenarios(9).AxisDeg = 55;
scenarios(9).Q = -0.58;
scenarios(9).ConeAmplitudeMm = 0.09;
scenarios(9).ConeCenterMm = [0.55, -0.75];
scenarios(9).ConeSigmaMm = 1.20;

scenarios(10).Name = "keratoconus_severe";
scenarios(10).SurfaceClass = "keratoconus-like";
scenarios(10).Severity = "severe";
scenarios(10).RflatMm = 7.05;
scenarios(10).RsteepMm = 6.30;
scenarios(10).AxisDeg = 70;
scenarios(10).Q = -0.75;
scenarios(10).ConeAmplitudeMm = 0.08;
scenarios(10).ConeCenterMm = [0.70, -1.00];
scenarios(10).ConeSigmaMm = 1.05;
end

function scenario = regularAstigmatism(base, name, severity, orientation, ...
        cylinderD, flatAxisDeg)
% Keep the mean nominal keratometric power at 43 D across orientations.
scenario = base;
scenario.Name = name;
scenario.SurfaceClass = "regular-astigmatism";
scenario.Severity = severity;
scenario.AstigmatismOrientation = orientation;
scenario.RflatMm = 337.5 / (43 - cylinderD / 2);
scenario.RsteepMm = 337.5 / (43 + cylinderD / 2);
scenario.AxisDeg = flatAxisDeg;
end
