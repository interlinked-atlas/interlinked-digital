
REVOKE EXECUTE ON FUNCTION public.reserve_install_slot(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.confirm_install_reservation(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.release_install_reservation(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.reserve_install_slot(uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.confirm_install_reservation(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_install_reservation(uuid) TO service_role;
