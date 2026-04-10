# Safe Integration Plan: UI & Icons Only

## Goal
Integrate ONLY UI improvements and icons from official repo WITHOUT changing:
- ❌ SearchBar (keep your semantic search toggle)
- ❌ SearchPage (keep your AI search integration)
- ❌ Any backend/API logic
- ❌ ConversationalAnalytics (keep your chat)
- ❌ AccessRequests (keep your flow)

## What TO Integrate

### Icons (60+ files) ✅
```bash
git checkout official/main -- src/assets/svg/aspect-*.svg
git checkout official/main -- public/assets/svg/knowledge-catalog-logo.svg
git checkout official/main -- public/assets/images/dataplex_icon_new.svg
git checkout official/main -- src/assets/svg/knowledge-catalog-logo.svg
git checkout official/main -- src/assets/svg/filter-*.svg
git checkout official/main -- src/assets/svg/database_schema_icon_blue.svg
```

### Filter Components ✅
```bash
git checkout official/main -- src/component/Common/FilterBar.tsx
git checkout official/main -- src/component/Common/FilterChipCarousel.tsx
git checkout official/main -- src/component/Common/FilterChipCarousel.css
git checkout official/main -- src/component/Common/OverflowTooltip.tsx
git checkout official/main -- src/component/BrowseByAnnotation/AspectFilterChip.tsx
git checkout official/main -- src/component/BrowseByAnnotation/AspectFilterInput.tsx
git checkout official/main -- src/component/BrowseByAnnotation/AspectFilterTypes.ts
git checkout official/main -- src/component/Filter/FilterDropDown.tsx
git checkout official/main -- src/component/Filter/FilterAnnotationsMultiSelect.tsx
```

### UI Components ✅
```bash
git checkout official/main -- src/component/Common/ResourcePreview.tsx
git checkout official/main -- src/component/Common/ResourcePreview.css
git checkout official/main -- src/component/Common/ResourceViewer.tsx
git checkout official/main -- src/component/Common/ThemedIconContainer.tsx
git checkout official/main -- src/component/Tags/FilterTag.tsx
git checkout official/main -- src/component/Tags/Tag.tsx
git checkout official/main -- src/component/Tags/Tag.css
```

### Supporting Files ✅
```bash
git checkout official/main -- src/constants/aspectIcons.ts
git checkout official/main -- src/constants/glossaryIcons.tsx
git checkout official/main -- src/component/Shimmer/ShimmerLoader.tsx
git checkout official/main -- src/component/Annotation/FieldItem.tsx
git checkout official/main -- src/component/Annotation/PreviewAnnotation.tsx
git checkout official/main -- src/component/Annotation/PreviewAnnotationSkeleton.tsx
git checkout official/main -- src/component/Annotation/AnnotationFilter.tsx
git checkout official/main -- src/contexts/NoAccessContext.tsx
git checkout official/main -- src/hooks/useColumnResize.ts
git checkout official/main -- src/component/Schema/ResizeHandle.tsx
git checkout official/main -- src/utils/debounce.ts
```

## What NOT to integrate (keep yours)

```bash
# ❌ DON'T touch these - they have your custom features:
# src/component/SearchBar/SearchBar.tsx  (your semantic search toggle)
# src/component/SearchBar/SearchBar.css
# src/component/SearchPage/SearchPage.tsx (your AI integration)
# src/component/SearchPage/SearchTableView.tsx
# src/component/SearchPage/NotificationBar.tsx
# src/component/SearchPage/SubmitAccess.tsx
# src/component/SearchEntriesCard/SearchEntriesCard.tsx
# src/component/SearchEntriesCard/SearchEntriesCard.css
# src/features/search/searchSlice.ts
# src/constants/urls.ts (your backend URLs)
# src/features/entry/entrySlice.ts
# src/utils/resourceUtils.ts
```

## Required Manual Fixes After Integration

1. Add to `src/constants/urls.ts`:
```typescript
CHECK_ENTRY_ACCESS: '/check-entry-access',
```

2. Add `checkEntryAccess` function to `src/features/entry/entrySlice.ts`:
```typescript
export const checkEntryAccess = createAsyncThunk(
  'entry/checkEntryAccess',
  async (requestData: { entryName: string; id_token: string }, { rejectWithValue }) => {
    if (!requestData) return rejectWithValue('No request data provided');
    try {
      axios.defaults.headers.common['Authorization'] = requestData.id_token
        ? `Bearer ${requestData.id_token}` : '';
      const response = await axios.get(
        URLS.API_URL + URLS.CHECK_ENTRY_ACCESS + `?entryName=${requestData.entryName}`
      );
      return { entryName: requestData.entryName, data: response.data };
    } catch (error) {
      if (error instanceof AxiosError) {
        return rejectWithValue({ entryName: requestData.entryName, error: error.response?.data || error.message });
      }
      return rejectWithValue({ entryName: requestData.entryName, error: 'An unknown error occurred' });
    }
  }
);
```

3. Update `EntryState` type and initialState to include `accessCheckCache`

4. Add reducer cases for `checkEntryAccess` (pending/fulfilled/rejected)

## Summary
- Total files to integrate: ~80 (mostly icons + UI components)
- Files to preserve: ~10 (your custom search + chat + access features)
- Build compatibility: Maintained
- Custom features: 100% preserved
