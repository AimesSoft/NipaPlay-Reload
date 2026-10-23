/// Kernel instances are numbered across all four kernels, in the order they
/// are made; every event and fact names its instance.
int _made = 0;
int nextKernelInstance() => ++_made;
