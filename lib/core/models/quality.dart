/// 音质档位（对齐 lx / MusicFree 常见档位）。
enum Quality { standard, high, superQuality, lossless, hires }

extension QualityLabel on Quality {
  String get label => switch (this) {
        Quality.standard => '128k',
        Quality.high => '320k',
        Quality.superQuality => '320k 高码率',
        Quality.lossless => '无损 FLAC',
        Quality.hires => 'Hi-Res',
      };
}
