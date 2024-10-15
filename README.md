# Usage

```dart
void main() async {
  int _kb = 1024;
  int _mb = _kb * _kb;

  void main() async {
    initMultimedia();
    late String th;

    await MediaPipeline([
      MagickImageLoaderJob(File("in.png")),
      ImageOptimizerWebPJob(output: File("image.webp"), maxDimension: 4096, maxBytes: 300 * _kb),
      ImageOptimizerWebPJob(output: File("thumb.webp"), maxDimension: 256, maxBytes: 3 * _kb),
      ImageScaleWebPJob(output: File("low.webp"), maxDimension: 512, quality: 15),
      ImageThumbHashJob(onThumbHash: (h) => th = h),
    ]).push();

    print("Thumbhash: $th");
  }
```