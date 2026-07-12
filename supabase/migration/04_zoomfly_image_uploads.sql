-- ================================================================
-- ZoomFly — 04_zoomfly_image_uploads.sql
-- Run AFTER 00, 01, 02, and 03, against STAGING first.
--
-- What this file does:
--   1. Fixes a real, currently-live bug: admin.html's package image
--      upload feature (handleImgUpload / the "+ Add Package" photo
--      dropzone) uploads to a bucket called 'zoomfly-images' — but
--      no migration ever created that bucket. Only 'avatars', 'media',
--      and 'logos' exist in the master schema, and none of those are
--      referenced by any actual upload code in the frontend. This
--      means every package photo upload has been failing outright
--      (or silently succeeding against a bucket that was manually
--      created once via the Supabase dashboard outside of any
--      migration, which wouldn't survive a fresh project setup and
--      isn't recorded anywhere). This migration creates the bucket
--      properly, with RLS matching the pattern already used for the
--      'logos' bucket: public read, admin-only write (tighter than
--      'media', which currently allows any authenticated user —
--      not just admins — to upload).
--   2. Tightens the 'media' bucket's policy, found unused-but-overly-
--      permissive while reviewing the fix above (any logged-in user
--      could upload, not just admins — unused today, fixed pre-emptively).
--   3. Adds a cover_image_url column to blog_posts so posts can use a
--      real uploaded photo instead of only an emoji + CSS gradient.
-- ================================================================

-- ----------------------------------------------------------------
-- 1. THE ACTUAL IMAGE STORAGE BUCKET
-- ----------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public) VALUES ('zoomfly-images','zoomfly-images',true) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public read zoomfly-images"  ON storage.objects;
DROP POLICY IF EXISTS "Admin upload zoomfly-images"  ON storage.objects;
DROP POLICY IF EXISTS "Admin update zoomfly-images"  ON storage.objects;
DROP POLICY IF EXISTS "Admin delete zoomfly-images"  ON storage.objects;

CREATE POLICY "Public read zoomfly-images" ON storage.objects FOR SELECT USING (bucket_id='zoomfly-images');
CREATE POLICY "Admin upload zoomfly-images" ON storage.objects FOR INSERT WITH CHECK (bucket_id='zoomfly-images' AND public.is_admin());
CREATE POLICY "Admin update zoomfly-images" ON storage.objects FOR UPDATE USING (bucket_id='zoomfly-images' AND public.is_admin());
CREATE POLICY "Admin delete zoomfly-images" ON storage.objects FOR DELETE USING (bucket_id='zoomfly-images' AND public.is_admin());

-- ----------------------------------------------------------------
-- 2. TIGHTEN AN UNUSED-BUT-OVERLY-PERMISSIVE BUCKET POLICY
-- ----------------------------------------------------------------
-- Found while reviewing storage policies for the fix above: the
-- 'media' bucket's insert/update policies only check
-- `auth.uid() IS NOT NULL` — i.e. ANY logged-in customer, not just
-- admins, despite this bucket clearly being intended for site content
-- (its sibling 'logos' bucket is correctly admin-only). No current
-- frontend code uploads to 'media' at all, so this hasn't been
-- exploitable in practice — but it's a live gap the moment anything
-- does start using it, so fixing it now while it's still unused costs
-- nothing and closes the door before it matters.
DROP POLICY IF EXISTS "Auth upload media" ON storage.objects;
DROP POLICY IF EXISTS "Auth update media" ON storage.objects;
CREATE POLICY "Admin upload media" ON storage.objects FOR INSERT WITH CHECK (bucket_id='media' AND public.is_admin());
CREATE POLICY "Admin update media" ON storage.objects FOR UPDATE USING (bucket_id='media' AND public.is_admin());

-- ----------------------------------------------------------------
-- 3. BLOG COVER IMAGES
-- ----------------------------------------------------------------
ALTER TABLE public.blog_posts ADD COLUMN IF NOT EXISTS cover_image_url TEXT;
-- NULL/empty means "use emoji + bg_gradient instead" (existing behavior,
-- unchanged) — this is purely additive, no existing post is affected
-- until an admin uploads a cover photo for it.
