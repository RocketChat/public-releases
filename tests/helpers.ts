import { expect } from 'bun:test'

export function assertEnvironmentVariableNotEmpty(variables: string[]) {
	variables.forEach(variable => expect(variable).not.toBeUndefined())
}