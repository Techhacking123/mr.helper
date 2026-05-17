import 'dart:convert';
import 'package:http/http.dart' as http;

class AISearchService {
  static const String _apiKey = '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';

  static Future<String?> analyzeSearchQuery({
    required String userQuery,
    required List<String> availableCategories,
  }) async {
    try {
      final url = Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions');
      
      final prompt = '''
        You are a smart search assistant for a home services app.
        The user searched for: "$userQuery"
        
        Our available service categories are: ${availableCategories.join(', ')}.
        
        Which category best matches the user's problem? 
        Respond with ONLY the exact name of the category from the list. 
        If none match, respond with "None".
      ''';

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          // Using Llama 3.1 8B Instruct which is widely available and fast on NVIDIA NIM
          'model': 'meta/llama-3.1-8b-instruct',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.1,
          'max_tokens': 20,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['choices'][0]['message']['content'].toString().trim();
        
        for (var category in availableCategories) {
          // Check for exact match or ignoring case/punctuation
          if (result.toLowerCase().contains(category.toLowerCase())) {
            return category;
          }
        }
      } else {
        print("AI Search API Error: ${response.statusCode} - ${response.body}");
      }
      return null;
    } catch (e) {
      print("AI Search Exception: $e");
      return null;
    }
  }
}
