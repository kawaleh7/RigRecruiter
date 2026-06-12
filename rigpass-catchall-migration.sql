-- ════════════════════════════════════════════════════════════════════
-- RIGPASS CATCH-ALL MIGRATION — June 2026
-- Fixes the "employment_type column not found" publish error
-- AND includes every recent migration in one safe script.
-- Safe to run multiple times (IF NOT EXISTS everywhere).
-- Run the WHOLE thing in Supabase SQL Editor.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. THE PUBLISH FIX: jobs.employment_type was never in the schema
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS employment_type text;

-- Drafts can be saved half-finished, so relax NOT NULL on title/trade
ALTER TABLE public.jobs ALTER COLUMN title DROP NOT NULL;
ALTER TABLE public.jobs ALTER COLUMN trade DROP NOT NULL;

-- ── 2. SCREENING QUESTIONS (from invite-screening migration)
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS screening_questions jsonb DEFAULT '[]'::jsonb;

ALTER TABLE public.applications
  ADD COLUMN IF NOT EXISTS screening_answers jsonb DEFAULT '[]'::jsonb;

-- ── 3. INVITATIONS TABLE (Invite to Apply)
CREATE TABLE IF NOT EXISTS public.invitations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employer_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  worker_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  job_id       uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  message      text,
  status       text NOT NULL DEFAULT 'sent' CHECK (status IN ('sent','viewed','applied','declined')),
  created_at   timestamptz DEFAULT now(),
  UNIQUE(worker_id, job_id)
);

CREATE INDEX IF NOT EXISTS inv_worker_idx ON public.invitations(worker_id);
CREATE INDEX IF NOT EXISTS inv_employer_idx ON public.invitations(employer_id);
CREATE INDEX IF NOT EXISTS inv_job_idx ON public.invitations(job_id);

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "inv_employer_all" ON public.invitations;
CREATE POLICY "inv_employer_all" ON public.invitations
  FOR ALL USING (auth.uid() = employer_id) WITH CHECK (auth.uid() = employer_id);

DROP POLICY IF EXISTS "inv_worker_read" ON public.invitations;
CREATE POLICY "inv_worker_read" ON public.invitations
  FOR SELECT USING (auth.uid() = worker_id);

DROP POLICY IF EXISTS "inv_worker_update" ON public.invitations;
CREATE POLICY "inv_worker_update" ON public.invitations
  FOR UPDATE USING (auth.uid() = worker_id) WITH CHECK (auth.uid() = worker_id);

DROP POLICY IF EXISTS "inv_admin_all" ON public.invitations;
CREATE POLICY "inv_admin_all" ON public.invitations
  FOR ALL USING (public.is_admin());

-- ── 4. PLAN EXPIRY (admin Set Plan feature)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS plan_expires_at timestamptz;

-- ── 5. WORKER JOB PREFERENCES (settings → Job Preferences tab)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferred_provinces text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS preferred_employment_types text[] DEFAULT '{}';

-- ── 6. TRADE LEVEL (1st Year Apprentice … Red Seal Journeyman)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS trade_level text;

-- ── DONE. Reload your app and publishing will work.
