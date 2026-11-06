begin;
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('business-documents','business-documents',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Business members read own documents" on storage.objects;
create policy "Business members read own documents" on storage.objects for select to authenticated
using (bucket_id='business-documents' and public.is_business_member((storage.foldername(name))[1]::uuid));
drop policy if exists "Business members upload own documents" on storage.objects;
create policy "Business members upload own documents" on storage.objects for insert to authenticated
with check (bucket_id='business-documents' and public.is_business_member((storage.foldername(name))[1]::uuid) and (storage.foldername(name))[2] is null);
drop policy if exists "Business admins delete own documents" on storage.objects;
create policy "Business admins delete own documents" on storage.objects for delete to authenticated
using (bucket_id='business-documents' and public.has_business_role((storage.foldername(name))[1]::uuid,array['owner','admin']::public.business_role[]));
commit;