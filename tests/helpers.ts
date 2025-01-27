import { expect } from "bun:test";
import { Octokit } from "octokit";

export function assertEnvironmentVariableNotEmpty(variables: string[]) {
  variables.forEach((variable) => expect(variable).not.toBeUndefined());
}

async function* _releases() {
  let page = 1;
  while (true) {
    yield new Octokit({}).rest.repos.listReleases({
      owner: "RocketChat",
      repo: "Rocket.Chat",
      page: page,
    });
    page++;
  }
}

// @ts-ignore-error
export async function findLastVersion(): Promise<string> {
  let next = false;
  for await (const release of _releases()) {
    if (release.data.tag_name == process.env.ROCKETCHAT_TAG) {
      next = true;
    }

    if (next && !release.data.prerelease) {
      return release.data.tag_name;
    }
  }
}
