export type Screenshot = {
  src: string;
  alt: string;
  caption: string;
  width: number;
  height: number;
};

/** Empty until real captures exist — the section hides itself when this is empty. */
export const SCREENSHOTS: readonly Screenshot[] = [];
