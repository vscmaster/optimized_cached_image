import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pedantic/pedantic.dart';

import 'image_transformer.dart';

class ImageCacheManager extends BaseCacheManager {
  final ImageCacheConfig cacheConfig;
  final ImageTransformer transformer;

  @override
  Future<String> getFilePath() async {
    if (cacheConfig.storagePath != null) {
      final Directory directory = await cacheConfig.storagePath;
      return directory.path;
    } else {
      final Directory directory = await getTemporaryDirectory();
      return p.join(directory.path, key);
    }
  }

  static const key = 'libCachedImageData';

  static ImageCacheManager _instance;

  /// The ScaledCacheManager that can be easily used directly. The code of
  /// this implementation can be used as inspiration for more complex cache
  /// managers.
  factory ImageCacheManager(
      {ImageCacheConfig cacheConfig, ImageTransformer transformer}) {
    final config = cacheConfig ?? ImageCacheConfig();
    _instance ??= ImageCacheManager._(
        config, transformer ?? DefaultImageTransformer(config));
    return _instance;
  }

  /// A named initializer for when clients wish to initialize the manager with custom config.
  /// This is purely for syntax purposes.
  factory ImageCacheManager.init(ImageCacheConfig cacheConfig,
      {ImageTransformer transformer}) {
    return ImageCacheManager(
        cacheConfig: cacheConfig, transformer: transformer);
  }

  ImageCacheManager._(this.cacheConfig, this.transformer) : super(key);

  ///Download the file and add to cache
  @override
  Future<FileInfo> downloadFile(String url,
      {Map<String, String> authHeaders, bool force = false}) async {
    var response =
        await super.downloadFile(url, authHeaders: authHeaders, force: force);
    response = await transformer.transform(response, url);
    return response;
  }

  /// Get the file from the cache and/or online, depending on availability and age.
  /// Downloaded form [url], [headers] can be used for example for authentication.
  /// The files are returned as stream. First the cached file if available, when the
  /// cached file is too old the newly downloaded file is returned afterwards.
  ///
  /// The [FileResponse] is either a [FileInfo] object for fully downloaded files
  /// or a [DownloadProgress] object for when a file is being downloaded.
  /// The [DownloadProgress] objects are only dispatched when [withProgress] is
  /// set on true and the file is not available in the cache. When the file is
  /// returned from the cache there will be no progress given, although the file
  /// might be outdated and a new file is being downloaded in the background.
  @override
  Stream<FileResponse> getFileStream(String url,
      {Map<String, String> headers, bool withProgress}) {
    final upStream =
        super.getFileStream(url, headers: headers, withProgress: withProgress);
    final downStream = StreamController<FileResponse>();
    var isUpStreamClosed = false;
    var awaitedItemsForProcessing =0;
    upStream.listen((d) async {
      ++awaitedItemsForProcessing;
      if (d is FileInfo) {
        d = await transformer.transform(d, url);
      }
      downStream.add(d);
      --awaitedItemsForProcessing;
      if (isUpStreamClosed) {
        unawaited(downStream.close());
      }
    }, onError: (e) {
      downStream.addError(e);
      downStream.close();
    }, onDone: () {
      isUpStreamClosed = true;
      if(awaitedItemsForProcessing==0){
        downStream.close();
      }
    });
    return downStream.stream;
  }
}

///
/// Helper method to transform image urls
///
String getDimensionSuffixedUrl(
    ImageCacheConfig config, String url, int width, int height) {
  Uri uri;
  try {
    uri = Uri.parse(url);
    if (uri != null) {
      Map<String, String> queryParams =
          Map<String, String>.from(uri.queryParameters);
      if (width != null) {
        queryParams[config.widthKey] = width.toString();
      }
      if (height != null) {
        queryParams[config.heightKey] = height.toString();
      }
      uri = uri.replace(queryParameters: queryParams);
    }
  } catch (e) {
    print('Error occured while parsing url $e');
  }
  return uri?.toString() ?? url;
}

abstract class ImageTransformer {
  Future<FileInfo> transform(FileInfo info, String uri);
}

class ImageCacheConfig {
  ///The url param name which holds the required width value
  final String widthKey;

  ///The url param name which holds the required height value
  final String heightKey;

  /// Storage path for cache
  final Future<Directory> storagePath;

  ImageCacheConfig(
      {this.widthKey = DEFAULT_WIDTH_KEY,
      this.heightKey = DEFAULT_HEIGHT_KEY,
      this.storagePath});

  static const DEFAULT_WIDTH_KEY = 'oci_width';
  static const DEFAULT_HEIGHT_KEY = 'oci_height';
}
