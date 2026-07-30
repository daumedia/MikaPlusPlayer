import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

/** Renders GitHub release bodies. Server-only, so none of this ships to the browser. */
export function ReleaseNotes({ markdown }: { markdown: string }) {
  if (!markdown.trim()) return null;

  return (
    <div className="prose prose-sm max-w-none prose-headings:font-display prose-headings:text-base">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // The page already owns h1/h2 — push release headings below them.
          h1: (props) => <h3 {...props} />,
          h2: (props) => <h3 {...props} />,
          a: ({ href, ...props }) => (
            <a href={href} target="_blank" rel="noopener noreferrer" {...props} />
          ),
          img: () => null,
          hr: () => null,
        }}
      >
        {markdown}
      </ReactMarkdown>
    </div>
  );
}
