# Third-party notices

## Microsoft SmartKC

This project is an independent MATLAB research implementation informed by the
[Microsoft SmartKC repository](https://github.com/microsoft/SmartKC-A-Smartphone-based-Corneal-Topographer),
including its published Arc-Step workflow and public reference attachment
geometry. The MATLAB code has been reorganized and modified substantially; it
is not an official Microsoft release. The U-Net architecture converter is
adapted from the upstream MIT-licensed Python implementation; the setup script
downloads the official checkpoint locally and does not commit it to this
repository. Deterministic inference parity is limited to the pinned conversion
fixture and is not a claim of clinical equivalence.

The upstream software is distributed under the following MIT License:

> Copyright (c) Microsoft Corporation.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

The upstream repository also applies Creative Commons Attribution 4.0 to
non-code licensed material. This project links to, but does not bundle, the
SmartKC and SmartKC++ publications.

## `fit_ellipse`

Ellipse fitting uses Ohad Gal's `fit_ellipse` MATLAB implementation, originally
published on MATLAB Central File Exchange in 2003:

https://www.mathworks.com/matlabcentral/fileexchange/3215-fit_ellipse

The unmodified fitting helper and its companion project axis-conversion helper
are stored at `functions/analysis/fit_ellipse.m` and
`functions/analysis/get_optometric_axes.m`. This keeps the active pipeline
self-contained and independent of the separate HealthEx recovery project.
