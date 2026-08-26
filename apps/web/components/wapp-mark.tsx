export function WappMark({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? "brand brand--compact" : "brand"}>
      <span className="brand__mark" aria-hidden="true">
        W
      </span>
      <span className="brand__name">Wapp</span>
    </div>
  );
}
