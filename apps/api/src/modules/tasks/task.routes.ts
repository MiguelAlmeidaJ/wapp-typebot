import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { enqueueTaskReminder } from "../../jobs/task-reminder.queue.js";
import { requirePermission } from "../auth/auth.guard.js";
import {
  cancelTask,
  completeTask,
  createTask,
  getContactTaskContext,
  listTasks,
  updateTask
} from "./task.service.js";

const idSchema = z.object({
  id: z.string().uuid()
});

const prioritySchema = z.enum([
  "LOW",
  "NORMAL",
  "HIGH",
  "URGENT"
]);

const createSchema = z.object({
  contactId: z.string().uuid(),
  ticketId: z.string().uuid().nullable().optional(),
  assigneeMembershipId: z.string().uuid(),
  title: z.string().trim().min(2).max(190),
  description: z.string().trim().max(10_000).nullable().optional(),
  priority: prioritySchema.default("NORMAL"),
  dueAt: z.string().datetime({
    offset: true
  }),
  reminderAt: z.string().datetime({
    offset: true
  }).nullable().optional()
});

const updateSchema = z.object({
  title: z.string().trim().min(2).max(190).optional(),
  description: z.string().trim().max(10_000).nullable().optional(),
  priority: prioritySchema.optional(),
  dueAt: z.string().datetime({
    offset: true
  }).optional(),
  reminderAt: z.string().datetime({
    offset: true
  }).nullable().optional(),
  ticketId: z.string().uuid().nullable().optional(),
  assigneeMembershipId: z.string().uuid().optional()
}).refine(value => Object.keys(value).length > 0, {
  message: "Informe ao menos uma alteração."
});

const listQuery = z.object({
  scope: z.enum([
    "ME",
    "ALL"
  ]).default("ME"),
  status: z.enum([
    "OPEN",
    "DONE",
    "CANCELLED"
  ]).default("OPEN"),
  contactId: z.string().uuid().optional(),
  overdueOnly: z.enum([
    "true",
    "false"
  ]).default("false").transform(value => value === "true"),
  limit: z.coerce.number().int().min(1).max(200).default(100)
});

export async function taskRoutes(app: FastifyInstance) {
  app.get("/api/v1/tasks", async request => {
    const auth = await requirePermission(request, "tasks.read");
    const query = listQuery.parse(request.query);

    return {
      tasks: await listTasks({
        companyId: auth.companyId,
        actorMembershipId: auth.membershipId,
        role: auth.role,
        ...query
      })
    };
  });

  app.get("/api/v1/contacts/:id/tasks/context", async request => {
    const auth = await requirePermission(request, "tasks.read");
    const params = idSchema.parse(request.params);

    return getContactTaskContext({
      companyId: auth.companyId,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      contactId: params.id
    });
  });

  app.post("/api/v1/tasks", async (request, reply) => {
    const auth = await requirePermission(request, "tasks.manage");
    const input = createSchema.parse(request.body);

    const task = await createTask({
      companyId: auth.companyId,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      ...input,
      dueAt: new Date(input.dueAt),
      reminderAt: input.reminderAt ? new Date(input.reminderAt) : null
    });

    let reminderQueued = false;

    if (task.reminderAt) {
      try {
        reminderQueued = await enqueueTaskReminder({
          taskId: task.id,
          reminderAt: task.reminderAt
        });
      } catch (error) {
        request.log.error({
          error,
          taskId: task.id
        }, "task reminder enqueue failed; sweep will reconcile");
      }
    }

    return reply.status(201).send({
      task,
      reminderQueued
    });
  });

  app.patch("/api/v1/tasks/:id", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);
    const input = updateSchema.parse(request.body);

    const {
      dueAt,
      reminderAt,
      ...taskChanges
    } =
      input;

    const task = await updateTask({
      companyId: auth.companyId,
      taskId: params.id,
      actorMembershipId: auth.membershipId,
      role: auth.role,
      ...taskChanges,
      ...(dueAt
        ? {
            dueAt: new Date(dueAt)
          }
        : {}),
      ...(reminderAt !== undefined
        ? {
            reminderAt: reminderAt ? new Date(reminderAt) : null
          }
        : {})
    });

    if (
      task.status === "OPEN" &&
      task.reminderAt &&
      !task.reminderSentAt &&
      !task.reminderFailedAt
    ) {
      try {
        await enqueueTaskReminder({
          taskId: task.id,
          reminderAt: task.reminderAt
        });
      } catch (error) {
        request.log.error({
          error,
          taskId: task.id
        }, "updated task reminder enqueue failed; sweep will reconcile");
      }
    }

    return {
      task
    };
  });

  app.post("/api/v1/tasks/:id/complete", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);

    return {
      task: await completeTask({
        companyId: auth.companyId,
        taskId: params.id,
        actorMembershipId: auth.membershipId,
        role: auth.role
      })
    };
  });

  app.post("/api/v1/tasks/:id/cancel", async request => {
    const auth = await requirePermission(request, "tasks.manage");
    const params = idSchema.parse(request.params);

    return {
      task: await cancelTask({
        companyId: auth.companyId,
        taskId: params.id,
        actorMembershipId: auth.membershipId,
        role: auth.role
      })
    };
  });
}
