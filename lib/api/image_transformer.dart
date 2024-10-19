import 'package:multimedia/api/pipeline_asset.dart';

abstract class ImageTransformer {
  final ImagePipelineAsset asset;

  ImageTransformer(this.asset);

  Future<ImagePipelineAsset> transform(ImagePipelineAsset asset);
}
