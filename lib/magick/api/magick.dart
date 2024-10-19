class MagickImage {
  MagickImage(this._image);

  final dynamic _image;

  int get width => _image.width;
  int get height => _image.height;

  void resize(int width, int height) {
    _image.resize(width, height);
  }

  void write(String path) {
    _image.write(path);
  }
}
