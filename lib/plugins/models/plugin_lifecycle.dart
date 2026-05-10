enum PluginLifecycleEvent {
  initialize('initialize'),
  destroy('destroy'),
  suspend('suspend'),
  resume('resume');

  const PluginLifecycleEvent(this.name);

  final String name;
}