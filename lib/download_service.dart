import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'search_models.dart';

class DownloadService {

  static Future<void> downloadSingleFile(String url, String title, String extension) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final cleanTitle = title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll('File:', '')
            .trim();
        final fileName = '$cleanTitle.${extension.toLowerCase()}';
        
        final blob = html.Blob([response.bodyBytes], response.headers['content-type'] ?? 'application/octet-stream');
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);
        
        html.AnchorElement(href: objectUrl)
          ..setAttribute("download", fileName)
          ..click();
          
        html.Url.revokeObjectUrl(objectUrl);
      }
    } catch (e) {
      print('Download failed: $e');
      html.window.open(url, '_blank');
    }
  }
  
  static Future<void> downloadBulkZip(List<SearchItem> items, {String zipName = 'commons_export.zip'}) async {
    if (items.isEmpty) return;

    final archive = Archive();

    for (var item in items) {
      try {
        final response = await http.get(Uri.parse(item.url));
        
        if (response.statusCode == 200) {
          final cleanTitle = item.title
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') 
              .replaceAll('File:', '')
              .trim();
              
          final fileName = '$cleanTitle.${item.extension.toLowerCase()}';
          
          final archiveFile = ArchiveFile(fileName, response.bodyBytes.length, response.bodyBytes);
          archive.addFile(archiveFile);
        }
      } catch (e) {
        print('Failed to fetch ${item.title}: $e');
      }
    }

    if (archive.isEmpty) return;

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;

    final blob = html.Blob([zipData], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    html.AnchorElement(href: url)
      ..setAttribute("download", zipName)
      ..click();
      
    html.Url.revokeObjectUrl(url);
  }
}