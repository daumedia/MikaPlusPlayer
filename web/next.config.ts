import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";

/**
 * Second line of defence behind the Markdown sanitising of release notes: nothing may load or
 * connect anywhere but this origin, no plugins, no framing, no <base> or form hijacking.
 *
 * 'unsafe-inline' for scripts is the price of static pages: the App Router streams its payload
 * in inline <script> tags, and the only alternative, a per-request nonce, forces every page to be
 * rendered dynamically (no static pages, no ISR). Styles need it for React style attributes.
 * 'unsafe-eval' only in `next dev`, which needs it for React Refresh.
 * No upgrade-insecure-requests: HSTS already covers production, and it breaks `next start` on
 * plain http://localhost.
 */
const contentSecurityPolicy = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self'",
  "font-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join("; ");

/** The site uses none of these browser features. */
const permissionsPolicy = [
  "accelerometer=()",
  "camera=()",
  "geolocation=()",
  "gyroscope=()",
  "magnetometer=()",
  "microphone=()",
  "payment=()",
  "usb=()",
  "browsing-topics=()",
].join(", ");

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
          {
            key: "Strict-Transport-Security",
            value: "max-age=63072000; includeSubDomains; preload",
          },
          { key: "Content-Security-Policy", value: contentSecurityPolicy },
          { key: "Permissions-Policy", value: permissionsPolicy },
        ],
      },
    ];
  },
};

export default nextConfig;
