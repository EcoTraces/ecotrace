import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_config.dart';

class CloudinaryUploadService {
  CloudinaryUploadService({ApiClient? apiClient, http.Client? httpClient})
    : _api = apiClient ?? ApiClient.instance,
      _http = httpClient ?? http.Client();

  static final instance = CloudinaryUploadService();
  final ApiClient _api;
  final http.Client _http;

  Future<String> uploadImage(
    Uint8List bytes, {
    required String scope,
    String fileName = 'image.jpg',
  }) async {
    if (!ApiConfig.enabled) {
      throw StateError('API_BASE_URL is required for Cloudinary uploads.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Image is empty.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw StateError('Images must be 10 MB or smaller.');
    }
    // Render free instances can sleep. A simple GET wakes the service without
    // requiring an authenticated CORS preflight before requesting a signature.
    await _api.get('/health', authenticated: false);
    final signed = await _api.post('/api/v1/media/upload-signature', {
      'scope': scope,
    });
    final request =
        http.MultipartRequest('POST', Uri.parse(signed['uploadUrl'].toString()))
          ..fields.addAll({
            'api_key': signed['apiKey'].toString(),
            'timestamp': signed['timestamp'].toString(),
            'folder': signed['folder'].toString(),
            'public_id': signed['publicId'].toString(),
            'signature': signed['signature'].toString(),
          })
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        body['error']?['message']?.toString() ??
            'Cloudinary image upload failed (${response.statusCode}).',
      );
    }
    final url = body['secure_url']?.toString();
    if (url == null || !url.startsWith('https://')) {
      throw const FormatException(
        'Cloudinary did not return a secure image URL.',
      );
    }
    return url;
  }

  Future<List<String>> uploadImages(
    List<Uint8List> files, {
    required String scope,
  }) async {
    final urls = <String>[];
    for (var index = 0; index < files.length; index++) {
      urls.add(
        await uploadImage(
          files[index],
          scope: scope,
          fileName: 'image-$index.jpg',
        ),
      );
    }
    return urls;
  }
}
