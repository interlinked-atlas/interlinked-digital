/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  async redirects() {
    return [
      // Canonicalize to www — without this, the apex and www domains are two
      // separate cookie origins, so a Supabase auth session set on one host
      // is invisible on the other, making users appear logged out when they
      // land on whichever host they weren't last on.
      {
        source: '/:path*',
        has: [{ type: 'host', value: 'interlinked.digital' }],
        destination: 'https://www.interlinked.digital/:path*',
        permanent: true,
      },
    ]
  },
}

export default nextConfig
