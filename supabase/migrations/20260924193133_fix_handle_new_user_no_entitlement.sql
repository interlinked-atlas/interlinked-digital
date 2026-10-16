-- P0-1: new signups must carry no plan value that could be mistaken for entitlement.
-- 'none' is a plain descriptive sentinel, not an entitlement grant — the sole
-- entitlement authority is subscriptions.status = 'active', checked elsewhere.
-- profiles.plan remains NOT NULL (Swift ATLASProfile.plan is a non-optional
-- String; making this column nullable would break profile JSON decoding).
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (id, email, plan, subscription_status)
  VALUES (new.id, new.email, 'none', 'inactive');
  RETURN new;
END;
$function$;