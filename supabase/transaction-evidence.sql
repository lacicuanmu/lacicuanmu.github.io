-- Laci Cuanmu: private storage for original transaction evidence
-- Run this once in Supabase Dashboard > SQL Editor.
-- The app stores only the private object path in the transaction record.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'transaction-evidence',
  'transaction-evidence',
  false,
  15728640,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/bmp',
    'image/tiff',
    'image/heic',
    'image/heif',
    'application/pdf'
  ]
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Laci Cuanmu evidence upload own folder" on storage.objects;
create policy "Laci Cuanmu evidence upload own folder"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'transaction-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Laci Cuanmu evidence read own folder" on storage.objects;
create policy "Laci Cuanmu evidence read own folder"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'transaction-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Laci Cuanmu evidence delete own folder" on storage.objects;
create policy "Laci Cuanmu evidence delete own folder"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'transaction-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
