require 'digest'
require 'fileutils'

# Erika 0.3.4 configures its CAMetalLayer from its presenter worker. On tvOS
# 26, changing a UIView backing layer there triggers UIKit's thread assertion.
# Give the renderer a standalone sublayer instead. Only the television Pod
# project compiles this generated copy; the Pub cache and other platforms stay
# untouched. Remove this adaptation after the upstream surface fix is shipped.
def nipa_patch_erika_tv_surface(target, sandbox)
  reference = target.source_build_phase.files.map(&:file_ref).compact.find do |file|
    file.path.end_with?('ErikaFlutterPlugin.swift')
  end
  raise 'Erika tvOS Swift source is missing' unless reference
  source = File.read(reference.real_path)
  expected = '996058faa1562d42b6082e20afa80ac41991f4d5e69f370b5e82ee6927ddbea3'
  unless Digest::SHA256.hexdigest(source) == expected
    raise 'Review the tvOS Metal surface adaptation before updating erika_flutter 0.3.4'
  end
  backing_layer = "  override class var layerClass: AnyClass { CAMetalLayer.self }\n\n" \
                  "  var metalLayer: CAMetalLayer { layer as! CAMetalLayer }\n"
  raise 'Expected two Erika television surfaces' unless source.scan(backing_layer).length == 2
  source = source.gsub(backing_layer, "  let metalLayer = CAMetalLayer()\n")
  marker = '    contentScaleFactor = CGFloat(currentScale)'
  raise 'Expected two Erika television initializers' unless source.scan(marker).length == 2
  setup = <<~SWIFT
    layer.addSublayer(metalLayer)
    metalLayer.actions = [
      "bounds": NSNull(), "position": NSNull(), "contentsScale": NSNull(),
      "drawableSize": NSNull(),
    ]
  SWIFT
  source = source.gsub(marker, marker + "\n" + setup.lines.map { |line| "    #{line}" }.join.chomp)
  backing_size_comment = /    \/\/ metalLayer is this view's \*backing\* layer[^\n]*\n(?:    \/\/[^\n]*\n){3}/
  raise 'Expected two Erika television size updates' unless source.scan(backing_size_comment).length == 2
  # Keep the view's frame in its parent, and the rendering sublayer in the view.
  source = source.gsub(backing_size_comment, "    metalLayer.frame = bounds\n")
  output = File.join(sandbox.to_s, 'NipaPlayErikaSources', 'ErikaFlutterPlugin.swift')
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, source)
  reference.path = output
  reference.source_tree = '<absolute>'
end
