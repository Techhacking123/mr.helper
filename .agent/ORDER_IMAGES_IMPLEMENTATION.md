# Order Image Upload Implementation Guide

## ✅ Implementation Complete - Place Order Page

The place order page now includes image upload functionality with the following features:
- Minimum 1 image required
- Maximum 4 images allowed
- Gallery and camera options
- Image preview with remove functionality
- Validation before submission

---

## 📋 Database Setup Required

### Step 1: Add Images Column to Orders Table

Run this SQL in your Supabase SQL Editor:

```sql
-- Add images column to store image URLs as JSON array
ALTER TABLE orders 
ADD COLUMN images JSONB DEFAULT '[]'::jsonb;

-- Add comment
COMMENT ON COLUMN orders.images IS 'Array of image URLs for the order';
```

### Step 2: Create Supabase Storage Bucket

1. Go to Your Supabase Project Dashboard
2. Navigate to "Storage" in the left sidebar
3. Click "Create Bucket"
4. **Bucket Name:** `order_images`
5. **Public bucket:** YES (check this box)
6. Click "Create Bucket"

### Step 3: Set Storage Bucket Policies

Run this SQL to set proper RLS policies for the storage bucket:

```sql
-- Allow anyone to upload (authenticated users only)
CREATE POLICY "Allow authenticated users to upload order images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'order_images');

-- Allow anyone to view (public access since bucket is public)
CREATE POLICY "Allow public to view order images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'order_images');

-- Allow users to delete their own order images
CREATE POLICY "Allow users to delete their order images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'order_images' AND auth.uid()::text = (storage.foldername(name))[1]);
```

---

## 🎯 Features Implemented in place_order.dart

### 1. Image Upload UI
- **Gallery Button:** Pick multiple images from gallery
- **Camera Button:** Take a photo with camera
- **Image Counter:** Shows current count (e.g., "2/4")
- **Validation Message:** Orange warning if no images selected

### 2. Image Preview
- **Grid Layout:** 3 columns displaying thumbnails
- **Remove Button:** Red X button on each image to remove
- **Visual Feedback:** Green check icon when images selected
- **Smart Limits:** Prevents selecting more than 4 total

### 3. Upload Process
- Images uploaded to Supabase Storage after order creation
- Folder structure: `{userId}/{orderId}/{filename}.jpg`
- URLs stored in orders table as JSON array
- Progress feedback during upload

### 4. Validation
- ✅ Minimum 1 image required
- ✅ Maximum 4 images enforced
- ✅ Clear error messages
- ✅ Cannot submit without images

---

## 📱 Next Steps: Display Images on Other Pages

### A. Display Images on Provider Requests Page

File: `lib/orders/provider_requests.dart`

**Where to Add:** In the request card that displays order details

**Code to Add:**

```dart
// Add this in the order card/tile where you display order info
if (order['images'] != null && (order['images'] as List).isNotEmpty) ...[
  const SizedBox(height: 8),
  const Text(
    'Order Images:',
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
    ),
  ),
  const SizedBox(height: 6),
  SizedBox(
    height: 80,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: (order['images'] as List).length,
      itemBuilder: (context, index) {
        final imageUrl = (order['images'] as List)[index];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              // Optional: Show full image in dialog
              showDialog(
                context: context,
                builder: (ctx) => Dialog(
                  child: Image.network(imageUrl),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.error),
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  ),
],
```

### B. Display Images on Order Detail Page

File: `lib/orders/order_detail.dart`

**Where to Add:** In the order details section

**Code to Add:**

```dart
// Add import at top
import 'package:flutter/material.dart';

// Add this in the order details UI
if (order['images'] != null && (order['images'] as List).isNotEmpty) ...[
  const SizedBox(height: 20),
  const Text(
    'Order Images',
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),
  const SizedBox(height: 12),
  GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1,
    ),
    itemCount: (order['images'] as List).length,
    itemBuilder: (context, index) {
      final imageUrl = (order['images'] as List)[index];
      return GestureDetector(
        onTap: () {
          // Show full-screen image
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      child: Image.network(imageUrl),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.broken_image,
                  size: 50,
                ),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
          ),
        ),
      );
    },
  ),
],
```

### C. Delete Images When Service Completed

File: `lib/orders/order_detail.dart`

**Where to Add:** In the "Service Completed" button handler

**Code to Add:**

```dart
// Add import at top
import '../supabase_config.dart';

// In the service completed function/handler:
Future<void> _markServiceCompleted(String orderId, List<dynamic>? images) async {
  try {
    // Delete images from storage if they exist
    if (images != null && images.isNotEmpty) {
      for (final imageUrl in images) {
        try {
          // Extract file path from URL
          final uri = Uri.parse(imageUrl.toString());
          final pathSegments = uri.pathSegments;
          
          // Find the path after 'order_images/'
          final bucketIndex = pathSegments.indexOf('order_images');
          if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
            final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
            
            // Delete from storage
            await SupabaseConfig.supabase.storage
                .from('order_images')
                .remove([filePath]);
            
            debugPrint('Deleted image: $filePath');
          }
        } catch (e) {
          debugPrint('Error deleting image: $e');
          // Continue even if one image fails to delete
        }
      }
    }
    
    // Clear images array in database
    await SupabaseConfig.supabase
        .from('orders')
        .update({'images': []})
        .eq('id', orderId);
    
    // Update order status to completed
    await SupabaseConfig.supabase
        .from('orders')
        .update({'status': 'completed'})
        .eq('id', orderId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service marked as completed! Images deleted.')),
      );
    }
  } catch (e) {
    debugPrint('Error completing service: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

// Call this function when "Service Completed" button is clicked
// Example button:
ElevatedButton(
  onPressed: () => _markServiceCompleted(
    order['id'].toString(),
    order['images'] as List<dynamic>?,
  ),
  child: const Text('SERVICE COMPLETED'),
)
```

---

## 🗂️ File Structure

Images are organized in Supabase Storage as follows:

```
order_images/
├── {userId1}/
│   ├── {orderId1}/
│   │   ├── {userId1}_{orderId1}_timestamp_0.jpg
│   │   ├── {userId1}_{orderId1}_timestamp_1.jpg
│   │   └── ...
│   └── {orderId2}/
│       └── ...
└── {userId2}/
    └── ...
```

---

## 🎯 Features Summary

### Place Order Page (`place_order.dart`) ✅
- [x] Image picker - Gallery
- [x] Image picker - Camera
- [x] Minimum 1 image validation
- [x] Maximum 4 images limit
- [x] Image preview grid
- [x] Remove individual images
- [x] Upload to Supabase Storage
- [x] Store URLs in database

### Provider Requests Page (`provider_requests.dart`) ⏳
- [ ] Display order images in horizontal list
- [ ] Tap to view full image
- [ ] Error handling for missing images

### Order Detail Page (`order_detail.dart`) ⏳
- [ ] Display order images in grid
- [ ] Interactive image viewer
- [ ] Delete images on service completion
- [ ] Clear images from database

---

## 🔧 Testing Checklist

### Before Testing:
1. ✅ Run SQL migration (add images column)
2. ✅ Create `order_images` bucket in Supabase Storage
3. ✅ Set bucket to Public
4. ✅ Add RLS policies for storage

### Test Steps:
1. **Place Order:**
   - [ ] Try submitting without images → Should show error
   - [ ] Add 1 image → Should allow submission
   - [ ] Add 4 images → Should show limit reached
   - [ ] Try adding 5th image → Should prevent
   - [ ] Remove images → Counter should update
   - [ ] Submit order → Images should upload

2. **Provider Requests:**
   - [ ] View order in requests list
   - [ ] Images should display as thumbnails
   - [ ] Tap image → Should show full view

3. **Order Details:**
   - [ ] Open order details
   - [ ] Images should display in grid
   - [ ] Tap image → Should zoom/full view
   - [ ] Click "Service Completed" → Images should delete

4. **Database Verification:**
   - [ ] Check orders table → images column should have URLs array
   - [ ] Check Storage → Files should exist
   - [ ] After completion → Files should be deleted

---

## ⚠️ Important Notes

1. **Storage Bucket Must Be Public:**
   - Images need to be publicly accessible
   - Set bucket to Public when creating

2. **Image Formats:**
   - Currently saves as `.jpg`
   - 70% quality to reduce size
   - Can be adjusted in code

3. **Error Handling:**
   - Images fail gracefully
   - Error icons shown for broken images
   - Upload errors prevent order creation

4. **Performance:**
   - Images compressed to 70% quality
   - Max 4 images limits data usage
   - Thumbnails load quickly

---

## 📝 Summary of Changes

### Files Modified:
1. **`lib/orders/place_order.dart`** (✅ Complete)
   - Added image picker imports
   - Added image state variables
   - Added _pickImages() method
   - Added _pickImageFromCamera() method
   - Added _removeImage() method
   - Added _uploadImages() method
   - Updated _submitRequest() with image upload
   - Added image upload UI section

### Files to Modify (Next):
2. **`lib/orders/provider_requests.dart`** (⏳ Pending)
   - Add image display in request cards

3. **`lib/orders/order_detail.dart`** (⏳  Pending)
   - Add image grid display
   - Add delete images on completion

### Database:
- **SQL Migration:** Add `images` column (JSONB)
- **Storage:** Create `order_images` bucket
- **RLS Policies:** Set storage permissions

---

**Implementation Status: 50% Complete**

✅ Place Order Page - DONE
⏳ Provider Requests Display - PENDING USER ACTION
⏳ Order Detail Display - PENDING USER ACTION
⏳ Delete on Completion - PENDING USER ACTION

---

All code snippets and instructions are ready to implement! 🎉
