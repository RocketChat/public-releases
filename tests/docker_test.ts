import { $ } from "bun";
import { beforeAll, describe, expect, it } from "bun:test";

import { assertEnvironmentVariableNotEmpty, findLastVersion } from "./helpers";

const { env } = process;

describe("Compose", () => {
  beforeAll(() => {
    assertEnvironmentVariableNotEmpty(["ROCKETCHAT_TAG", "COMPOSE_FILE"]);
  });

  it("should be a valid compose file", async () => {
    const { stderr, exitCode } =
      await $`docker compose -f ${process.env.COMPOSE_FILE} config -q`
        .nothrow()
        .quiet();

    if (exitCode) {
      console.error(stderr.toString())
    }

    expect(exitCode).toBe(0);
  });

  it("should deploy fine with an empty .env", async () => {
    // const project_name = basename(env.PWD as string)
    //   .replaceAll(".", "")
    //   .toLowerCase();

    const structure =
      await $`docker compose -f ${env.COMPOSE_FILE} config --format json`.json();

    const expected = {
      mongodb: {
        MONGODB_ADVERTISED_HOSTNAME: "mongodb",
        MONGODB_INITIAL_PRIMARY_HOST: "mongodb",
        MONGODB_INITIAL_PRIMARY_PORT_NUMBER: "27017",
      },
      rocketchat: {
        MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0",
        ROOT_URL: "http://localhost:3000",
      },
    };

    const assertVariable = (service: string, variable: string, value: string) =>
      expect(structure.services[service].environment[variable]).toBe(value);

    Object.entries(expected).map(([service, environment]) =>
      Object.entries(environment).map(([variable, value]) =>
        assertVariable(service, variable, value)
      )
    );
  });

  it("should generate the right config after modifying environment variables", async () => {
    const _env = {
      PORT: 3001,
      BIND_IP: "127.0.0.1",
      HOST_PORT: 80,
      MONGODB_REPLICA_SET_NAME: "rocket_rs0",
      MONGODB_PORT_NUMBER: 27018,
      MONGODB_INITIAL_PRIMARY_PORT_NUMBER: 27018,
      RELEASE: env.ROCKETCHAT_TAG,
    };

    let envStr = "";
    Object.entries(_env).map(
      ([variable, value]) => (envStr += `${variable}=${value}\n`)
    );

    await $`echo ${envStr} > .env`;
    
    console.log(await findLastVersion())
  });
});
