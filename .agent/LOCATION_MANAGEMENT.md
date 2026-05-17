# Location Management Feature - Complete Guide

## Overview
Admin can now add, edit, and manage locations that appear throughout the app (signup, order creation, etc.).

## Implementation

### 1. Database Setup
**File**: `.agent/locations_table_setup.sql`

**Run this in Supabase SQL Editor to create the locations table:**
- Creates `locations` table with `name`, `is_active`, timestamps
- Adds RLS policies for security
- Inserts default locations (Mumbai, Delhi, Bangalore, etc.)
- Creates trigger for auto-updating timestamps

### 2. Admin UI Changes
**File**: `lib/admin/admin_services.dart`

**Changes Made**:
- Added TabBar with "Services" and "Locations" tabs
- Integrated location management in second tab
- Fetches locations from database on page load

**File**: `lib/admin/admin_locations.dart` (NEW)

**Features**:
- ✅ View all locations (active and inactive separately)
- ✅ Add new location with name and active status
- ✅ Edit existing location
- ✅ Delete location
- ✅ Toggle active/inactive status
- ✅ Beautiful UI with color-coded active/inactive states

### 3. How Locations Are Used in App

**Signup Page** (`lib/auth/signup.dart`):
- Already fetches from `locations` table
- Shows dropdownfor location selection
- Only shows `is_active = true` locations

**Order Page** (needs to be checked):
- Should fetch from `locations` table
- Display active locations in dropdown

**Any Other Location Dropdowns**:
- Will automatically use the `locations` table
- Only active locations are shown to users

## Features

### For Admin:

1. **Add Location**:
   - Click "+" floating button
   - Enter location name
   - Toggle active/inactive
   - Click "Add"

2. **Edit Location**:
   - Click edit icon on location card
   - Modify name or status
   - Click "Save"

3. **Activate/Deactivate**:
   - Click visibility icon
   - Location immediately hides/shows from user dropdowns

4. **Delete Location**:
   - Click delete icon
   - Confirm deletion
   - Location removed from database

### Visual Indicators:

- **Active Locations**: Green badge, visible eye icon
- **Inactive Locations**: Red badge, hidden eye icon
- Grouped separately for easy management

## Database Schema

```sql
CREATE TABLE locations (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);
```

## How to Use

### Initial Setup:
1. Run `locations_table_setup.sql` in Supabase
2. Hot reload Flutter app
3. Navigate to Admin Dashboard → "Manage Services"
4. Switch to "Locations" tab

### Adding New Location:
1. Click "+ Add Location" button
2. Enter city/region name (e.g., "Jaipur")
3. Ensure "Active" is toggled ON
4. Click "Add"
5. Location now appears in all app dropdowns!

### Deactivating Location (without deleting):
1. Find the location in the list
2. Click the visibility icon
3. Location turns red and won't show to users
4. Data is preserved in database

### Editing Location:
1. Click edit icon (pencil)
2. Modify name or status
3. Click "Save"

## Integration Points

The `locations` table is already integrated in:
- ✅ **Signup Page**: User/Provider location selection
- ⚠️ **Order Page**: May need to verify integration
- ⚠️ **Profile Pages**: Check if location dropdowns exist

### Recommended: Update All Location Dropdowns

Search for hardcoded location lists in your codebase and replace with database fetch:

```dart
// OLD (hardcoded):
final locations = ['Mumbai', 'Delhi', 'Bangalore'];

// NEW (from database):
final response = await SupabaseConfig.supabase
    .from('locations')
    .select('name')
    .eq('is_active', true)
    .order('name');
final locations = List<Map<String, dynamic>>.from(response);
```

## Benefits

1. **Centralized Management**: All locations in one place
2. **No Code Changes**: Add/remove locations without app update
3. **Instant Updates**: Changes reflect immediately
4. **Data Integrity**: Can't accidentally have mismatched locations
5. **Analytics Ready**: Track which locations are popular
6. **Scalability**: Easy to expand to new cities

## Testing

1. **Add a test location**: "Test City"
2. **Go to Signup page**: Verify it appears in dropdown
3. **Deactivate it**: Check it disappears from dropdown
4. **Reactivate it**: Check it reappears
5. **Delete it**: Verify complete removal

## Future Enhancements (Optional)

- Add location metadata (state, country, lat/long)
- Show usage statistics per location
- Bulk upload locations via CSV
- Location-specific service availability
- Geolocation-based auto-selection

---

**Note**: The locations table is separate from services, so you can manage both independently in the same admin page using tabs!
