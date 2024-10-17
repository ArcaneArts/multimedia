# Usage

```dart
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

# Use in docker
To get image processing working in a docker image that runs dart servers you would make an image like so 

```dockerfile
# Stage 1: Build ImageMagick
FROM debian:bullseye-slim AS imagemagick-builder

# Install build dependencies
RUN apt-get update
RUN apt-get install -y build-essential
RUN apt-get install -y wget
RUN apt-get install -y libpng-dev
RUN apt-get install -y libjpeg-dev
RUN apt-get install -y libtiff-dev
RUN apt-get install -y libwebp-dev

# Download and compile ImageMagick
WORKDIR /tmp
RUN wget https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.1-15.tar.gz
RUN tar xvzf 7.1.1-15.tar.gz
WORKDIR /tmp/ImageMagick-7.1.1-15
RUN ./configure --disable-hdri --with-quantum-depth=8
RUN make
RUN make install

# Stage 2: Final image with Dart and ImageMagick
FROM dart:stable

# Copy ImageMagick from the builder stage
COPY --from=imagemagick-builder /usr/local /usr/local

# Update the library cache
RUN ldconfig

# Set up the Dart application
WORKDIR /app
COPY pubspec.* ./
COPY subpackages ./subpackages
RUN dart pub get
COPY . .

EXPOSE 8080

# If you intend to use AOT you need to copy out the libs in lib/libraries and manually initalize multimedia because
# AOT wont let us copy out resources stripped during build. Its easier to just use JIT
CMD ["dart", "run", "bin/server.dart"]
```