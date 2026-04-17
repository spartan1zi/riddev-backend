import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        primary: {
          DEFAULT: "#f59e0b",
          dark: "#d97706",
        },
      },
      fontFamily: {
        sans: ["var(--font-inter)", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      boxShadow: {
        glass:
          "0 8px 30px rgba(0,0,0,0.06), 0 1px 0 rgba(255,255,255,0.8) inset",
        "glass-lg": "8px 0 40px rgba(0,0,0,0.06)",
      },
    },
  },
  plugins: [],
};
export default config;
