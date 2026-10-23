import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { type Language, LANGUAGES, type MessageKey, MESSAGES } from "./messages.js";

/**
 * The page's language: Polish unless this browser chose English (ADR-573 makes Polish Doddy's
 * default). The choice is a per-browser convenience in localStorage; it may be unavailable
 * (private windows, blocked storage), and then the page simply starts in Polish.
 */

const STORAGE_KEY = "doddy.web.language";

export function storedLanguage(): Language {
  try {
    const value = window.localStorage.getItem(STORAGE_KEY);
    if (value && (LANGUAGES as readonly string[]).includes(value)) return value as Language;
  } catch {
    // Storage blocked: the default.
  }
  return "pl";
}

function remember(language: Language): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, language);
  } catch {
    // Not kept; it still applies to this visit.
  }
}

export function format(template: string, values: Record<string, string | number> = {}): string {
  return template.replace(/\{(\w+)\}/g, (whole, name: string) => (name in values ? String(values[name]) : whole));
}

interface I18n {
  language: Language;
  setLanguage(language: Language): void;
  t(key: MessageKey, values?: Record<string, string | number>): string;
  /** "22 Oct 2026, 10:00" in the page's language. */
  dateTime(iso: string): string;
  date(iso: string): string;
  bytes(size: number): string;
}

const Context = createContext<I18n | null>(null);

export function I18nProvider({ children, initial }: { children: ReactNode; initial?: Language }) {
  const [language, setState] = useState<Language>(initial ?? storedLanguage());
  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);
  const setLanguage = useCallback((next: Language) => {
    remember(next);
    setState(next);
  }, []);
  const value = useMemo<I18n>(() => {
    const locale = language === "pl" ? "pl-PL" : "en-GB";
    const dateTimeFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" });
    const dateFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });
    const number = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 });
    return {
      language,
      setLanguage,
      t: (key, values) => format(MESSAGES[language][key], values),
      dateTime: (iso) => dateTimeFormat.format(new Date(iso)),
      date: (iso) => dateFormat.format(new Date(iso)),
      bytes: (size) => (size < 1024 ? `${size} B` : size < 1024 * 1024 ? `${number.format(size / 1024)} KB` : `${number.format(size / (1024 * 1024))} MB`),
    };
  }, [language, setLanguage]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useI18n(): I18n {
  const value = useContext(Context);
  if (!value) throw new Error("useI18n outside I18nProvider");
  return value;
}
