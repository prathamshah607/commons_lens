import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'search_models.dart'; // To access your SearchItem model

class DownloadService {

  /// Fetches a single file and forces the browser to download it directly
  static Future<void> downloadSingleFile(String url, String title, String extension) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        // Clean the filename so the OS accepts it
        final cleanTitle = title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll('File:', '')
            .trim();
        final fileName = '$cleanTitle.${extension.toLowerCase()}';
        
        // Create the Blob and object URL
        final blob = html.Blob([response.bodyBytes], response.headers['content-type'] ?? 'application/octet-stream');
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);
        
        // Force the download
        html.AnchorElement(href: objectUrl)
          ..setAttribute("download", fileName)
          ..click();
          
        // Clean up memory
        html.Url.revokeObjectUrl(objectUrl);
      }
    } catch (e) {
      print('Download failed: $e');
      // Ultimate fallback: if a strict CORS policy blocks the fetch, just open the tab
      html.window.open(url, '_blank');
    }
  }
  
  /// Takes a list of SearchItems, fetches their bytes, zips them, and triggers a download.
  static Future<void> downloadBulkZip(List<SearchItem> items, {String zipName = 'commons_export.zip'}) async {
    if (items.isEmpty) return;

    // 1. Initialize an empty archive
    final archive = Archive();

    // 2. Fetch each file sequentially
    for (var item in items) {
      try {
        final response = await http.get(Uri.parse(item.url));
        
        if (response.statusCode == 200) {
          // Clean up the filename so it's safe for Windows/Mac
          final cleanTitle = item.title
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') 
              .replaceAll('File:', '')
              .trim();
              
          final fileName = '$cleanTitle.${item.extension.toLowerCase()}';
          
          // Add the raw bytes to the archive
          final archiveFile = ArchiveFile(fileName, response.bodyBytes.length, response.bodyBytes);
          archive.addFile(archiveFile);
        }
      } catch (e) {
        // If one file fails (e.g., a CORS issue or dead link), we catch it and continue
        print('Failed to fetch ${item.title}: $e');
      }
    }

    // 3. If the archive is empty (all failed), abort.
    if (archive.isEmpty) return;

    // 4. Encode the archive to a Zip format
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;

    // 5. Create a browser Blob and trigger the download
    final blob = html.Blob([zipData], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    html.AnchorElement(href: url)
      ..setAttribute("download", zipName)
      ..click(); // Simulate a user clicking the link
      
    // 6. Clean up the memory immediately after triggering the download
    html.Url.revokeObjectUrl(url);
  }
}