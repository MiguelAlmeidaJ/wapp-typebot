export type Role = "OWNER" | "ADMIN" | "SUPERVISOR" | "AGENT";

export interface AuthUser {
  id: string;
  name: string;
  email: string;
}

export interface AuthCompany {
  id: string;
  name: string;
  slug: string;
}

export interface AuthSession {
  user: AuthUser;
  company: AuthCompany;
  role: Role;
}

export interface LoginResponse extends AuthSession {
  accessToken: string;
}

export interface RefreshResponse {
  accessToken: string;
}

export interface CompanyChoice {
  membershipId: string;
  role: Role;
  company: AuthCompany;
}

export interface CompanyRequiredDetails {
  companies?: CompanyChoice[];
}
