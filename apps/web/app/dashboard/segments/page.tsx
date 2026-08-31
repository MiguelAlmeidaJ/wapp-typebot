"use client";

import { type FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";
import { roleCan } from "@/lib/permissions";

type BinaryFilter = "ANY" | "YES" | "NO";
type LastSeenFilter = "ANY" | "WITHIN_7D" | "WITHIN_30D" | "WITHIN_90D" | "NEVER";
type FollowUpFilter = "ANY" | "OPEN" | "OVERDUE" | "NONE";
type CustomOperator = "EQ" | "NEQ" | "CONTAINS" | "EMPTY" | "NOT_EMPTY";

interface CustomCriterion {
  fieldId: string;
  operator: CustomOperator;
  value: string | null;
}

interface SegmentDefinition {
  search: string | null;
  hasPhone: BinaryFilter;
  hasEmail: BinaryFilter;
  lastSeen: LastSeenFilter;
  customFields: CustomCriterion[];
  pipeline: { pipelineId: string; stageIds: string[]; includeUnassigned: boolean } | null;
  followUp: FollowUpFilter;
}

interface Field {
  id: string;
  label: string;
  type: "TEXT" | "NUMBER" | "DATE" | "BOOLEAN" | "SELECT";
  options: unknown;
}

interface Stage {
  id: string;
  name: string;
  colorKey: string;
  outcome: "OPEN" | "WON" | "LOST";
}

interface Pipeline {
  id: string;
  name: string;
  description: string | null;
  stages: Stage[];
}

interface Segment {
  id: string;
  name: string;
  description: string | null;
  definition: SegmentDefinition;
  isActive: boolean;
  updatedAt: string;
  createdByMembership: { id: string; user: { id: string; name: string } } | null;
}

interface PreviewContact {
  id: string;
  name: string;
  phoneNumber: string | null;
  email: string | null;
  lastSeenAt: string | null;
  pipelineStates: Array<{
    id: string;
    pipeline: { id: string; name: string };
    stage: { id: string; name: string; colorKey: string; outcome: string };
  }>;
  crmTasks: Array<{ id: string; title: string; priority: string; dueAt: string }>;
  tickets: Array<{ id: string; status: string; lastMessage: string | null; lastMessageAt: string }>;
}

interface Preview {
  count: number;
  truncated: boolean;
  contacts: PreviewContact[];
}

const EMPTY_DEFINITION: SegmentDefinition = {
  search: null,
  hasPhone: "ANY",
  hasEmail: "ANY",
  lastSeen: "ANY",
  customFields: [],
  pipeline: null,
  followUp: "ANY"
};

const operatorLabels: Record<CustomOperator, string> = {
  EQ: "É igual a",
  NEQ: "É diferente de",
  CONTAINS: "Contém",
  EMPTY: "Está vazio",
  NOT_EMPTY: "Está preenchido"
};

function cloneDefinition(value: SegmentDefinition): SegmentDefinition {
  return JSON.parse(JSON.stringify(value)) as SegmentDefinition;
}

function hasCriteria(value: SegmentDefinition) {
  return Boolean(
    value.search?.trim() ||
    value.hasPhone !== "ANY" ||
    value.hasEmail !== "ANY" ||
    value.lastSeen !== "ANY" ||
    value.customFields.length ||
    value.pipeline ||
    value.followUp !== "ANY"
  );
}

function optionsOf(field: Field) {
  return Array.isArray(field.options)
    ? field.options.filter((item): item is string => typeof item === "string")
    : [];
}

function dateTimeLabel(value: string | null) {
  if (!value) return "Nunca";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

export default function SegmentsPage() {
  const router = useRouter();
  const { session, loading, request, subscribe } = useAuth();
  const [segments, setSegments] = useState<Segment[]>([]);
  const [fields, setFields] = useState<Field[]>([]);
  const [pipelines, setPipelines] = useState<Pipeline[]>([]);
  const [selectedSegmentId, setSelectedSegmentId] = useState<string | null>(null);
  const [segmentName, setSegmentName] = useState("");
  const [description, setDescription] = useState("");
  const [definition, setDefinition] = useState<SegmentDefinition>(() => cloneDefinition(EMPTY_DEFINITION));
  const [customFieldId, setCustomFieldId] = useState("");
  const [customOperator, setCustomOperator] = useState<CustomOperator>("EQ");
  const [customValue, setCustomValue] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(true);
  const [previewing, setPreviewing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const canManage = session ? roleCan(session.role, "segments.manage") : false;
  const selectedSegment = useMemo(
    () => segments.find(segment => segment.id === selectedSegmentId) ?? null,
    [segments, selectedSegmentId]
  );
  const selectedField = useMemo(
    () => fields.find(field => field.id === customFieldId) ?? null,
    [customFieldId, fields]
  );
  const selectedPipeline = useMemo(
    () => pipelines.find(item => item.id === definition.pipeline?.pipelineId) ?? null,
    [definition.pipeline?.pipelineId, pipelines]
  );

  const loadBase = useCallback(async () => {
    const [segmentPayload, context] = await Promise.all([
      request<{ segments: Segment[] }>(canManage ? "/api/v1/segments/manage" : "/api/v1/segments"),
      request<{ fields: Field[]; pipelines: Pipeline[] }>("/api/v1/segments/context")
    ]);
    setSegments(segmentPayload.segments);
    setFields(context.fields);
    setPipelines(context.pipelines);
  }, [canManage, request]);

  const previewDefinition = useCallback(async (value: SegmentDefinition) => {
    if (!hasCriteria(value)) {
      setPreview(null);
      setError("Adicione ao menos um critério antes de visualizar.");
      return;
    }
    setPreviewing(true);
    setError("");
    try {
      const payload = await request<Preview>("/api/v1/segments/preview", {
        method: "POST",
        body: JSON.stringify({ definition: value, limit: 60 })
      });
      setPreview(payload);
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível calcular o segmento.");
    } finally {
      setPreviewing(false);
    }
  }, [request]);

  useEffect(() => {
    if (!loading && !session) {
      router.replace("/login");
      return;
    }
    if (session && !roleCan(session.role, "segments.view")) {
      router.replace("/dashboard");
      return;
    }
    if (session) {
      setBusy(true);
      void loadBase()
        .catch(() => setError("Não foi possível carregar os segmentos."))
        .finally(() => setBusy(false));
    }
  }, [loadBase, loading, router, session]);

  useEffect(() => {
    if (!session) return;
    return subscribe("/api/v1/realtime/events", event => {
      if (event.type === "segment.updated") void loadBase();
      if ((event.type === "contact.pipeline.updated" || event.type === "task.updated") && preview && hasCriteria(definition)) {
        void previewDefinition(definition);
      }
    });
  }, [definition, loadBase, preview, previewDefinition, session, subscribe]);

  function resetBuilder() {
    setSelectedSegmentId(null);
    setSegmentName("");
    setDescription("");
    setDefinition(cloneDefinition(EMPTY_DEFINITION));
    setPreview(null);
    setNotice("");
    setError("");
  }

  function selectSegment(segment: Segment) {
    const next = cloneDefinition(segment.definition);
    setSelectedSegmentId(segment.id);
    setSegmentName(segment.name);
    setDescription(segment.description ?? "");
    setDefinition(next);
    setNotice("");
    setError("");
    void previewDefinition(next);
  }

  function setPipelineId(pipelineId: string) {
    setDefinition(current => ({
      ...current,
      pipeline: pipelineId ? { pipelineId, stageIds: [], includeUnassigned: true } : null
    }));
  }

  function toggleStage(stageId: string) {
    setDefinition(current => {
      if (!current.pipeline) return current;
      const exists = current.pipeline.stageIds.includes(stageId);
      return {
        ...current,
        pipeline: {
          ...current.pipeline,
          stageIds: exists
            ? current.pipeline.stageIds.filter(id => id !== stageId)
            : [...current.pipeline.stageIds, stageId]
        }
      };
    });
  }

  function operatorsFor(field: Field): CustomOperator[] {
    return field.type === "TEXT"
      ? ["EQ", "NEQ", "CONTAINS", "EMPTY", "NOT_EMPTY"]
      : ["EQ", "NEQ", "EMPTY", "NOT_EMPTY"];
  }

  function addCustomCriterion(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedField) return;
    if (definition.customFields.some(item => item.fieldId === selectedField.id)) {
      setError("Esse campo já está sendo usado no segmento.");
      return;
    }
    const needsValue = !["EMPTY", "NOT_EMPTY"].includes(customOperator);
    if (needsValue && !customValue.trim()) {
      setError("Informe o valor do campo personalizado.");
      return;
    }
    setDefinition(current => ({
      ...current,
      customFields: [
        ...current.customFields,
        {
          fieldId: selectedField.id,
          operator: customOperator,
          value: needsValue ? customValue.trim() : null
        }
      ]
    }));
    setCustomFieldId("");
    setCustomOperator("EQ");
    setCustomValue("");
    setError("");
  }

  function removeCriterion(fieldId: string) {
    setDefinition(current => ({
      ...current,
      customFields: current.customFields.filter(item => item.fieldId !== fieldId)
    }));
  }

  async function saveSegment() {
    if (!canManage) return;
    if (!segmentName.trim()) {
      setError("Informe um nome para o segmento.");
      return;
    }
    if (!hasCriteria(definition)) {
      setError("Adicione ao menos um critério ao segmento.");
      return;
    }
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const payload = await request<{ segment: Segment }>(
        selectedSegmentId ? `/api/v1/segments/${selectedSegmentId}` : "/api/v1/segments",
        {
          method: selectedSegmentId ? "PATCH" : "POST",
          body: JSON.stringify({
            name: segmentName.trim(),
            description: description.trim() || null,
            definition
          })
        }
      );
      setSelectedSegmentId(payload.segment.id);
      setNotice(selectedSegmentId ? "Segmento atualizado." : "Segmento salvo.");
      await loadBase();
      await previewDefinition(definition);
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível salvar o segmento.");
    } finally {
      setSaving(false);
    }
  }

  async function toggleArchive() {
    if (!canManage || !selectedSegment) return;
    setSaving(true);
    setError("");
    try {
      await request(`/api/v1/segments/${selectedSegment.id}`, {
        method: "PATCH",
        body: JSON.stringify({ isActive: !selectedSegment.isActive })
      });
      setNotice(selectedSegment.isActive ? "Segmento arquivado." : "Segmento reativado.");
      await loadBase();
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : "Não foi possível alterar o segmento.");
    } finally {
      setSaving(false);
    }
  }

  function renderCustomValue(field: Field) {
    if (["EMPTY", "NOT_EMPTY"].includes(customOperator)) return null;
    if (field.type === "SELECT") {
      return (
        <select value={customValue} onChange={event => setCustomValue(event.target.value)}>
          <option value="">Selecionar…</option>
          {optionsOf(field).map(option => <option key={option} value={option}>{option}</option>)}
        </select>
      );
    }
    if (field.type === "BOOLEAN") {
      return (
        <select value={customValue} onChange={event => setCustomValue(event.target.value)}>
          <option value="">Selecionar…</option>
          <option value="true">Sim</option>
          <option value="false">Não</option>
        </select>
      );
    }
    return (
      <input
        type={field.type === "NUMBER" ? "number" : field.type === "DATE" ? "date" : "text"}
        value={customValue}
        onChange={event => setCustomValue(event.target.value)}
      />
    );
  }

  if (loading || !session) return <main className="dashboard-loading">Carregando segmentos…</main>;

  return (
    <main className="segments-screen">
      <header className="segments-header">
        <div>
          <button className="connections-back" onClick={() => router.push("/dashboard")} type="button">← Visão geral</button>
          <span className="eyebrow">CRM</span>
          <h1>Segmentos</h1>
          <p>Audiências dinâmicas com dados do contato, Perfil 360º, pipeline e follow-ups.</p>
        </div>
        <button className="ghost-button" onClick={resetBuilder} type="button">Novo filtro</button>
      </header>

      {error && <div className="segments-feedback segments-feedback--error">{error}</div>}
      {notice && <div className="segments-feedback">{notice}</div>}

      <section className="segments-layout">
        <aside className="segment-saved-list">
          <header><strong>Salvos</strong><span>{segments.length}</span></header>
          <div>
            {segments.map(segment => (
              <button
                key={segment.id}
                className={
                  selectedSegmentId === segment.id
                    ? "segment-saved-item segment-saved-item--active"
                    : segment.isActive
                      ? "segment-saved-item"
                      : "segment-saved-item segment-saved-item--archived"
                }
                onClick={() => selectSegment(segment)}
                type="button"
              >
                <div><strong>{segment.name}</strong><small>{segment.description ?? "Sem descrição"}</small></div>
                <span>{segment.isActive ? "Ativo" : "Arquivado"}</span>
              </button>
            ))}
            {!busy && segments.length === 0 && <div className="segments-empty">Nenhum segmento salvo.</div>}
          </div>
        </aside>

        <section className="segment-builder">
          <header>
            <div><strong>{selectedSegmentId ? "Editar segmento" : "Construtor"}</strong><span>Os critérios são combinados com “E”.</span></div>
            {canManage && (
              <div>
                {selectedSegment && (
                  <button className="ghost-button" disabled={saving} onClick={() => void toggleArchive()} type="button">
                    {selectedSegment.isActive ? "Arquivar" : "Reativar"}
                  </button>
                )}
                <button className="primary-button" disabled={saving} onClick={() => void saveSegment()} type="button">
                  <span>{saving ? "Salvando…" : selectedSegmentId ? "Salvar alterações" : "Salvar segmento"}</span>
                </button>
              </div>
            )}
          </header>

          {canManage && (
            <div className="segment-identity-fields">
              <label><span>Nome</span><input maxLength={140} value={segmentName} onChange={event => setSegmentName(event.target.value)} placeholder="Ex.: Leads quentes sem follow-up" /></label>
              <label><span>Descrição</span><input maxLength={500} value={description} onChange={event => setDescription(event.target.value)} placeholder="Uso interno opcional" /></label>
            </div>
          )}

          <div className="segment-filter-grid">
            <label><span>Busca</span><input value={definition.search ?? ""} onChange={event => setDefinition(current => ({ ...current, search: event.target.value || null }))} placeholder="Nome, WhatsApp, telefone ou e-mail" /></label>
            <label><span>Telefone</span><select value={definition.hasPhone} onChange={event => setDefinition(current => ({ ...current, hasPhone: event.target.value as BinaryFilter }))}><option value="ANY">Qualquer</option><option value="YES">Com telefone</option><option value="NO">Sem telefone</option></select></label>
            <label><span>E-mail</span><select value={definition.hasEmail} onChange={event => setDefinition(current => ({ ...current, hasEmail: event.target.value as BinaryFilter }))}><option value="ANY">Qualquer</option><option value="YES">Com e-mail</option><option value="NO">Sem e-mail</option></select></label>
            <label><span>Última atividade</span><select value={definition.lastSeen} onChange={event => setDefinition(current => ({ ...current, lastSeen: event.target.value as LastSeenFilter }))}><option value="ANY">Qualquer</option><option value="WITHIN_7D">Últimos 7 dias</option><option value="WITHIN_30D">Últimos 30 dias</option><option value="WITHIN_90D">Últimos 90 dias</option><option value="NEVER">Nunca visto</option></select></label>
            <label><span>Follow-up</span><select value={definition.followUp} onChange={event => setDefinition(current => ({ ...current, followUp: event.target.value as FollowUpFilter }))}><option value="ANY">Qualquer</option><option value="OPEN">Com tarefa aberta</option><option value="OVERDUE">Com tarefa atrasada</option><option value="NONE">Sem tarefa aberta</option></select></label>
            <label><span>Pipeline</span><select value={definition.pipeline?.pipelineId ?? ""} onChange={event => setPipelineId(event.target.value)}><option value="">Não filtrar</option>{pipelines.map(pipeline => <option key={pipeline.id} value={pipeline.id}>{pipeline.name}</option>)}</select></label>
          </div>

          {definition.pipeline && selectedPipeline && (
            <div className="segment-stage-filter">
              <div>
                <strong>Etapas em {selectedPipeline.name}</strong>
                <label><input type="checkbox" checked={definition.pipeline.includeUnassigned} onChange={event => setDefinition(current => current.pipeline ? ({ ...current, pipeline: { ...current.pipeline, includeUnassigned: event.target.checked } }) : current)} /> Sem etapa</label>
              </div>
              <div className="segment-stage-options">
                {selectedPipeline.stages.map(stage => (
                  <label key={stage.id}>
                    <input type="checkbox" checked={definition.pipeline?.stageIds.includes(stage.id) ?? false} onChange={() => toggleStage(stage.id)} />
                    <span className={`pipeline-stage-color pipeline-stage-color--${stage.colorKey.toLowerCase()}`} />
                    {stage.name}
                  </label>
                ))}
              </div>
            </div>
          )}

          <section className="segment-custom-fields">
            <header><div><strong>Campos personalizados</strong><span>Filtros do Perfil 360º.</span></div></header>
            <form className="segment-custom-form" onSubmit={addCustomCriterion}>
              <select value={customFieldId} onChange={event => {
                const fieldId = event.target.value;
                setCustomFieldId(fieldId);
                const field = fields.find(item => item.id === fieldId);
                setCustomOperator(field ? operatorsFor(field)[0] : "EQ");
                setCustomValue("");
              }}>
                <option value="">Escolher campo…</option>
                {fields.filter(field => !definition.customFields.some(item => item.fieldId === field.id)).map(field => <option key={field.id} value={field.id}>{field.label}</option>)}
              </select>
              <select disabled={!selectedField} value={customOperator} onChange={event => {
                const next = event.target.value as CustomOperator;
                setCustomOperator(next);
                if (["EMPTY", "NOT_EMPTY"].includes(next)) setCustomValue("");
              }}>
                {(selectedField ? operatorsFor(selectedField) : ["EQ"] as CustomOperator[]).map(operator => <option key={operator} value={operator}>{operatorLabels[operator]}</option>)}
              </select>
              {selectedField ? renderCustomValue(selectedField) : <input disabled placeholder="Valor" />}
              <button className="ghost-button" disabled={!selectedField} type="submit">Adicionar</button>
            </form>
            <div className="segment-custom-chips">
              {definition.customFields.map(criterion => {
                const field = fields.find(item => item.id === criterion.fieldId);
                return (
                  <span key={criterion.fieldId}>
                    <strong>{field?.label ?? "Campo"}</strong> {operatorLabels[criterion.operator]}{criterion.value ? ` “${criterion.value}”` : ""}
                    <button onClick={() => removeCriterion(criterion.fieldId)} type="button">×</button>
                  </span>
                );
              })}
              {definition.customFields.length === 0 && <small>Nenhum campo personalizado no filtro.</small>}
            </div>
          </section>

          <div className="segment-preview-action">
            <button className="primary-button" disabled={previewing || !hasCriteria(definition)} onClick={() => void previewDefinition(definition)} type="button"><span>{previewing ? "Calculando…" : "Visualizar audiência"}</span></button>
            <small>A audiência é recalculada com os dados atuais; nenhum contato é congelado no segmento.</small>
          </div>
        </section>

        <section className="segment-preview">
          <header>
            <div><strong>Audiência</strong><span>{preview ? `${preview.count} contatos encontrados` : "Aguardando prévia"}</span></div>
            {preview?.truncated && <small>Exibindo os primeiros 60 resultados.</small>}
          </header>
          <div className="segment-preview__list">
            {preview?.contacts.map(contact => (
              <article className="segment-contact-card" key={contact.id}>
                <button className="segment-contact-card__identity" onClick={() => router.push(`/dashboard/contacts?contact=${contact.id}`)} type="button">
                  <span>{contact.name.slice(0, 1).toUpperCase()}</span>
                  <div><strong>{contact.name}</strong><small>{contact.phoneNumber ?? contact.email ?? "Sem telefone/e-mail"}</small></div>
                </button>
                {contact.pipelineStates.length > 0 && <div className="segment-contact-card__stages">{contact.pipelineStates.map(state => <span key={state.id}>{state.pipeline.name}: <strong>{state.stage.name}</strong></span>)}</div>}
                <div className="segment-contact-card__footer">
                  <span>Última atividade: {dateTimeLabel(contact.lastSeenAt)}</span>
                  {contact.crmTasks[0] && <span>Follow-up: <strong>{contact.crmTasks[0].title}</strong></span>}
                </div>
                {contact.tickets[0] && <button className="segment-contact-card__conversation" onClick={() => router.push(`/dashboard/conversations?ticket=${contact.tickets[0].id}`)} type="button">Abrir última conversa</button>}
              </article>
            ))}
            {preview && preview.contacts.length === 0 && <div className="segments-empty">Nenhum contato corresponde a esses critérios.</div>}
            {!preview && <div className="segments-empty">Monte os critérios e clique em “Visualizar audiência”.</div>}
          </div>
        </section>
      </section>
    </main>
  );
}
