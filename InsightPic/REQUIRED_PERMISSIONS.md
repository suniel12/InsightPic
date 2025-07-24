# Required Info.plist Permissions

Add these entries to your Info.plist or project settings in Xcode:

## Photo Library Access
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>InsightPic needs access to your photo library to analyze and curate your best photos.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>InsightPic may save processed versions of your photos back to your library.</string>
```

## How to Add in Xcode:

1. **Method 1: Project Settings**
   - Select your project in Xcode
   - Go to the "Info" tab
   - Add new entries:
     - Key: `Privacy - Photo Library Usage Description`
     - Value: `InsightPic needs access to your photo library to analyze and curate your best photos.`
     - Key: `Privacy - Photo Library Additions Usage Description`
     - Value: `InsightPic may save processed versions of your photos back to your library.`

2. **Method 2: Info.plist file** (if you have one)
   - Add the XML entries above to your Info.plist file

## Additional Permissions (Optional)
If you want to access location data from photos:

```xml
<key>NSLocationUsageDescription</key>
<string>InsightPic uses location data from your photos to provide location-based photo grouping.</string>
```