// import { Editor, Extension } from "@tiptap/core";
import { keymap } from "@tiptap/pm/keymap";

// Yjs imports (no WebsocketProvider since we're using custom WebSocket)
import Dexie, { type EntityTable } from "dexie";

import {
  LoroSyncPlugin,
  LoroUndoPlugin,
  redo,
  undo,
  CursorAwareness,
  LoroCursorPlugin,
} from "loro-prosemirror";

import {
  LoroDoc,
  LoroTree,
  LoroTreeNode,
  LoroMap,
  LoroText,
  ContainerID,
  TreeID,
} from "loro-crdt";

import * as sdk from "matrix-js-sdk";
const ROOT_DOC_KEY = "0@14167320934836008919";
let matrixClient: sdk.MatrixClient;

import { AutoDiscovery } from "matrix-js-sdk";
import {
  isLivekitFocusConfig,
  LivekitFocus,
} from "matrix-js-sdk/src/matrixrtc/LivekitFocus";
import {
  MatrixRTCSession,
  MatrixRTCSessionEvent,
} from "matrix-js-sdk/src/matrixrtc/MatrixRTCSession";

const FOCI_WK_KEY = "org.matrix.msc4143.rtc_foci";

import { MatrixClient, type IOpenIDToken } from "matrix-js-sdk/src/matrix";
import { logger } from "matrix-js-sdk/src/logger";

import { Room, RoomEvent } from "livekit-client";
import { sleep } from "matrix-js-sdk/src/utils";

export interface SFUConfig {
  url: string;
  jwt: string;
}
export type OpenIDClientParts = Pick<
  MatrixClient,
  "getOpenIdToken" | "getDeviceId"
>;

function getRandomAnimalName() {
  const animals = [
    "Lion",
    "Tiger",
    "Elephant",
    "Giraffe",
    "Zebra",
    "Monkey",
    "Panda",
    "Koala",
    "Kangaroo",
    "Dolphin",
    "Whale",
    "Shark",
    "Eagle",
    "Owl",
    "Parrot",
    "Penguin",
    "Flamingo",
    "Bear",
    "Wolf",
    "Fox",
    "Rabbit",
    "Deer",
    "Horse",
    "Cat",
    "Hamster",
    "Hedgehog",
    "Squirrel",
    "Raccoon",
    "Otter",
    "Seal",
    "Turtle",
    "Frog",
    "Butterfly",
    "Bee",
    "Ladybug",
    "Spider",
    "Octopus",
    "Jellyfish",
    "Starfish",
    "Crab",
    "Lobster",
    "Shrimp",
    "Salmon",
    "Tuna",
    "Goldfish",
    "Seahorse",
    "Crocodile",
    "Lizard",
    "Snake",
    "Chameleon",
  ];

  return animals[Math.floor(Math.random() * animals.length)];
}

// Function to get a random color in hex format
function getRandomColor() {
  const colors = [
    "#6DFF7E", // Green
    "#FF6D6D", // Red
    "#6D9EFF", // Blue
    "#FFD66D", // Yellow
    "#FF6DFF", // Magenta
    "#6DFFFF", // Cyan
    "#FF9D6D", // Orange
    "#A06DFF", // Purple
    "#FF6DA0", // Pink
    "#6DFFA0", // Mint
    "#FFA06D", // Peach
    "#A0FF6D", // Lime
    "#6DA0FF", // Sky Blue
    "#FF6DDE", // Hot Pink
    "#DFF6D6", // Light Green
    "#FFB3BA", // Light Pink
    "#BAFFC9", // Light Mint
    "#BAE1FF", // Light Blue
    "#FFFFBA", // Light Yellow
    "#FFDFBA", // Light Orange
  ];

  return colors[Math.floor(Math.random() * colors.length)];
}

export async function makePreferredLivekitFoci(
  rtcSession: MatrixRTCSession,
  livekitAlias: string,
  matrix_client: MatrixClient
): Promise<LivekitFocus[]> {
  console.log("Start building foci_preferred list: ", rtcSession.room.roomId);

  const preferredFoci: LivekitFocus[] = [];

  // Prioritize the .well-known/matrix/client, if available, over the configured SFU
  const domain = matrix_client.getDomain();
  if (domain) {
    // we use AutoDiscovery instead of relying on the MatrixClient having already
    // been fully configured and started
    const wellKnownFoci = (await AutoDiscovery.getRawClientConfig(domain))?.[
      FOCI_WK_KEY
    ];
    if (Array.isArray(wellKnownFoci)) {
      preferredFoci.push(
        ...wellKnownFoci
          .filter((f) => !!f)
          .filter(isLivekitFocusConfig)
          .map((wellKnownFocus) => {
            console.log(
              "Adding livekit focus from well known: ",
              wellKnownFocus
            );
            return { ...wellKnownFocus, livekit_alias: livekitAlias };
          })
      );
    }
  }
  return preferredFoci;
}
async function getLiveKitJWT(
  client: OpenIDClientParts,
  livekitServiceURL: string,
  roomName: string,
  openIDToken: IOpenIDToken
): Promise<SFUConfig> {
  try {
    const res = await fetch(livekitServiceURL + "/sfu/get", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        room: roomName,
        openid_token: openIDToken,
        device_id: client.getDeviceId(),
      }),
    });
    if (!res.ok) {
      throw new Error("SFU Config fetch failed with status code " + res.status);
    }
    const sfuConfig = await res.json();
    console.log(
      "MatrixRTCExample: get SFU config: \nurl:",
      sfuConfig.url,
      "\njwt",
      sfuConfig.jwt
    );
    return sfuConfig;
  } catch (e) {
    throw new Error("SFU Config fetch failed with exception " + e);
  }
}

export async function getSFUConfigWithOpenID(
  client: OpenIDClientParts,
  activeFocus: LivekitFocus
): Promise<SFUConfig | undefined> {
  const openIdToken = await client.getOpenIdToken();
  logger.debug("Got openID token", openIdToken);

  try {
    logger.info(
      `Trying to get JWT from call's active focus URL of ${activeFocus.livekit_service_url}...`
    );
    const sfuConfig = await getLiveKitJWT(
      client,
      activeFocus.livekit_service_url,
      activeFocus.livekit_alias,
      openIdToken
    );
    logger.info(`Got JWT from call's active focus URL.`);

    return sfuConfig;
  } catch (e) {
    logger.warn(
      `Failed to get JWT from RTC session's active focus URL of ${activeFocus.livekit_service_url}.`,
      e
    );
    return undefined;
  }
}
//@ts-ignore
import { Ok, Error } from "../gleam.mjs";

export function save_document() {
  const messageEvent = new CustomEvent("save_doc");
  document.dispatchEvent(messageEvent);
}

export async function save_function(room_id: string, doc: LoroDoc) {
  let files = await get_all_update_files();

  let array_files = files?.map((updateString) => {
    if (updateString) {
      const binaryString = atob(updateString);
      const snapshot = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        snapshot[i] = binaryString.charCodeAt(i);
      }

      return [...snapshot];
    }
  });
  if (array_files) {
    console.log(array_files);
    //@ts-ignore
    doc.importBatch(array_files);
  }

  const snapshot = doc.export({ mode: "snapshot" });
  await save_loro_doc(room_id, snapshot);

  sync_to_repo(snapshot);

  const messageEvent = new CustomEvent("state_saved");
  document.dispatchEvent(messageEvent);
}

export function user_selected_note(note_id: String) {
  const messageEvent = new CustomEvent("user-selected-note", {
    detail: note_id,
  });
  document.dispatchEvent(messageEvent);
}

export function download_notebook(doc: LoroDoc) {
  let snapshot = doc.export({ mode: "snapshot" });
  // Convert Uint8Array to Blob
  const blob = new Blob([snapshot], { type: "application/octet-stream" });

  // Create download link
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "MyNoteBook.bin"; // or whatever filename you want
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
//@ts-ignore
import { render_editor } from "./main.jsx";
import { joinRoom } from "trystero";
import { Octokit } from "octokit";

export async function init_tiptap(doc: LoroDoc) {
  let room_id = "noter";
  const config = { appId: "sakwdakwdakowdapkwdpkwdkemonas" };
  const room = joinRoom(config, "errgaeaerrgf");

  const awareness = new CursorAwareness(doc.peerIdStr);

  const mainApp = document.querySelector("#main-app");

  let selected_document;

  // // let awareness;
  // let tiptapEditor: Editor | undefined;
  let livekitRoom: Room;
  let tiptapEditor;
  let blocknoteEditor: BlockNoteEditor | undefined;
  document.addEventListener("save_doc", () => {
    save_function(room_id, doc);
  });
  document.addEventListener("user-selected-note", (e) => {
    if (tiptapEditor) {
      tiptapEditor.destroy();

      //@ts-ignore
      selected_document = e.detail;
      let container = doc.getMap(selected_document);
      const LoroPlugins = Extension.create({
        name: "loro-plugins",
        addProseMirrorPlugins() {
          return [
            LoroSyncPlugin({
              //@ts-ignore
              doc,
              containerId: container.id,
            }),
            LoroUndoPlugin({ doc }),
            LoroCursorPlugin(awareness, {
              user: {
                name: getRandomAnimalName(),
                color: getRandomColor(),
              },
            }),
            keymap({ "Mod-z": undo, "Mod-y": redo, "Mod-Shift-z": redo }),
          ];
        },
      });

      render_editor(LoroPlugins, (tiptapEditor, blocknoteEditor) => {
        tiptapEditor = tiptapEditor;
        blocknoteEditor = blocknoteEditor;
      });
    } else {
      //@ts-ignore
      selected_document = e.detail;
      let container = doc.getMap(selected_document);
      const LoroPlugins = Extension.create({
        name: "loro-plugins",
        addProseMirrorPlugins() {
          return [
            LoroSyncPlugin({
              //@ts-ignore
              doc,
              containerId: container.id,
            }),
            LoroUndoPlugin({ doc }),
            LoroCursorPlugin(awareness, {
              user: {
                name: getRandomAnimalName(),
                color: getRandomColor(),
              },
            }),
            keymap({ "Mod-z": undo, "Mod-y": redo, "Mod-Shift-z": redo }),
          ];
        },
      });

      render_editor(LoroPlugins, (tiptapEditor, blocknoteEditor) => {
        tiptapEditor = tiptapEditor;
        blocknoteEditor = blocknoteEditor;
      });
    }
  });

  const [sendUpdate, getUpdate] = room.makeAction("update");
  const [sendAwareness, getAwareness] = room.makeAction("awareness");

  room.onPeerJoin((peer_id) => {
    let update = doc.export({ mode: "snapshot" });

    sendUpdate(update, peer_id);
  });

  getUpdate((update, peer) => {
    //@ts-ignore
    doc.import(update);
  });

  doc.subscribe((e) => {
    let update = doc.export({ mode: "update" });

    sendUpdate(update);
  });
  let debounceTimer;
  getAwareness((update, peer) => {
    //@ts-ignore
    awareness.apply(update);
  });
  awareness.addListener(async (update, origin) => {
    // Clear existing timer
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    // Set new timer with 100ms delay
    debounceTimer = setTimeout(async () => {
      if (origin === "local") {
        if (selected_document) {
          const update = awareness.encode([doc.peerIdStr]);
          sendAwareness(update);
        }
      }
    }, 0);
  });

  //     livekitRoom.on("participantConnected", async (participant) => {

  //       const writer = await livekitRoom.localParticipant.streamBytes({
  //         // All byte streams must have a name, which is like a filename
  //         name: "loro-update",
  //         // Fixed typo: "updare" -> "update"
  //         topic: "loro-update",
  //       });

  //       const chunkSize = 15000; // 15KB, a recommended max chunk size

  //       // Stream the Uint8Array update data in chunks
  //       for (let i = 0; i < update.length; i += chunkSize) {
  //         const chunk = update.slice(i, i + chunkSize);
  //         await writer.write(chunk);
  //       }

  //       await writer.close();
  //     });
  //     livekitRoom.on("connected", async () => {
  //       let update = doc.export({ mode: "update" });

  //       const writer = await livekitRoom.localParticipant.streamBytes({
  //         // All byte streams must have a name, which is like a filename
  //         name: "loro-update",
  //         // Fixed typo: "updare" -> "update"
  //         topic: "loro-update",
  //       });

  //       const chunkSize = 15000; // 15KB, a recommended max chunk size

  //       // Stream the Uint8Array update data in chunks
  //       for (let i = 0; i < update.length; i += chunkSize) {
  //         const chunk = update.slice(i, i + chunkSize);
  //         await writer.write(chunk);
  //       }

  //       await writer.close();

  //       doc.subscribe(async (e) => {
  //         let update = doc.export({ mode: "update" });

  //         const writer = await livekitRoom.localParticipant.streamBytes({
  //           // All byte streams must have a name, which is like a filename
  //           name: "loro-update",
  //           // Fixed typo: "updare" -> "update"
  //           topic: "loro-update",
  //         });

  //         const chunkSize = 15000; // 15KB, a recommended max chunk size

  //         // Stream the Uint8Array update data in chunks
  //         for (let i = 0; i < update.length; i += chunkSize) {
  //           const chunk = update.slice(i, i + chunkSize);
  //           await writer.write(chunk);
  //         }

  //         await writer.close();
  //       });

  //       let debounceTimer;

  //       awareness.addListener(async (update, origin) => {
  //         // Clear existing timer
  //         if (debounceTimer) {
  //           clearTimeout(debounceTimer);
  //         }

  //         // Set new timer with 100ms delay
  //         debounceTimer = setTimeout(async () => {
  //           if (origin === "local") {
  //             if (selected_document) {
  //               const update = awareness.encode([doc.peerIdStr]);

  //               const writer = await livekitRoom.localParticipant.streamBytes({
  //                 // All byte streams must have a name, which is like a filename
  //                 name: selected_document,
  //                 // Fixed typo: "updare" -> "update"
  //                 topic: "loro-awareness",
  //               });

  //               const chunkSize = 15000; // 15KB, a recommended max chunk size

  //               // Stream the Uint8Array update data in chunks
  //               for (let i = 0; i < update.length; i += chunkSize) {
  //                 const chunk = update.slice(i, i + chunkSize);
  //                 await writer.write(chunk);
  //               }

  //               await writer.close();
  //             }
  //           }
  //         }, 100);
  //       });
  //     });

  //     livekitRoom.registerByteStreamHandler(
  //       "loro-update",
  //       async (reader, participantInfo) => {
  //         const info = reader.info;

  //         // Option 2: Get the entire file after the stream completes.
  //         const result = new Blob(await reader.readAll(), {
  //           type: info.mimeType,
  //         });

  //         const update = new Uint8Array(await result.arrayBuffer());
  //         doc.import(update);
  //       }
  //     );
  //     livekitRoom.registerByteStreamHandler(
  //       "loro-awareness",
  //       async (reader, participantInfo) => {
  //         const info = reader.info;

  //         // Option 2: Get the entire file after the stream completes.
  //         const result = new Blob(await reader.readAll(), {
  //           type: info.mimeType,
  //         });

  //         const update = new Uint8Array(await result.arrayBuffer());
  //         awareness.apply(update);
  //       }
  //     );
  //   }
  // });
}

export async function sync_to_repo(update: Uint8Array) {
  let device_id = localStorage.getItem("github_device_id");

  if (!device_id) {
    device_id = crypto.randomUUID();
    localStorage.setItem("github_device_id", device_id);
  }

  let github_token = localStorage.getItem("github_token");
  const octokit = new Octokit({ auth: github_token });

  const filePath = device_id + "update.bin";

  try {
    // First, try to get the existing file to retrieve its SHA
    let sha;
    try {
      const existingFile = await octokit.rest.repos.getContent({
        owner: "kemo-1",
        repo: "test_repo",
        // branch: "p2p-notebook",
        path: filePath,
      });

      // If file exists, get its SHA
      if (
        !Array.isArray(existingFile.data) &&
        existingFile.data.type === "file"
      ) {
        sha = existingFile.data.sha;
      }
    } catch (error) {
      // File doesn't exist yet, that's fine - we'll create it
      console.log("File doesn't exist yet, creating new file");
    }

    // Create or update the file
    const response = await octokit.rest.repos.createOrUpdateFileContents({
      owner: "kemo-1",
      // branch: "p2p-notebook",
      repo: "test_repo",
      content: btoa(String.fromCharCode(...update)),
      path: filePath,
      message: "uploaded snapshot",
      ...(sha && { sha }), // Only include SHA if we have one
    });

    console.log("File uploaded successfully:", response.data);
  } catch (error) {
    console.error("Upload failed:", error);
  }
}

export async function get_all_update_files() {
  let github_token = localStorage.getItem("github_token");
  const octokit = new Octokit({ auth: github_token });

  try {
    const response = await octokit.rest.git.getTree({
      owner: "kemo-1",
      repo: "test_repo",
      tree_sha: "HEAD",
    });

    const updateFiles = response.data.tree.filter(
      (item) => item.type === "blob" && item.path?.endsWith("update.bin")
    );

    const filesWithContent = await Promise.all(
      updateFiles.map(async (file) => {
        try {
          const content = await octokit.rest.repos.getContent({
            owner: "kemo-1",
            repo: "test_repo",
            // branch: "p2p-notebook",

            path: file.path!,
          });

          if (!Array.isArray(content.data) && content.data.type === "file") {
            // Decode base64 content to Uint8Array
            const base64Content = content.data.content;

            return base64Content;
          }
        } catch (error) {
          console.error(`Failed to get content for ${file.path}:`, error);
          return null;
        }
      })
    );

    // Filter out any failed requests
    const validFiles = filesWithContent.filter((file) => file !== null);
    return validFiles;
  } catch (error) {
    console.error(`Failed to get content for `);
    return null;
  }
}

export function delete_db() {
  indexedDB.deleteDatabase("matrix-js-sdk::matrix-sdk-crypto");
}

import {
  draggable,
  dropTargetForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { Extension } from "@tiptap/core";
import { BlockNoteEditor } from "@blocknote/core";

export function make_draggable(folders_and_items: [HTMLElement]) {
  folders_and_items.forEach((element) => {
    draggable({
      element: element,
    });
  });
}

export function make_drop_target(
  folders: [HTMLElement],
  handleDragEnter,
  handleDragLeave,
  handleDrop
) {
  folders.forEach((folder_element) => {
    dropTargetForElements({
      element: folder_element,
      canDrop(e) {
        let item = e.source.element.dataset.drag_id;
        let drop_target = folder_element.dataset.drag_id;
        if (item === drop_target) {
          return false;
        }
        if (
          folder_element.dataset.drag_id === e.source.element.dataset.parent_id
        ) {
          return false;
        }
        if (
          folder_element.dataset.drag_id === folder_element.dataset.parent_id
        ) {
          return false;
        } else {
          return true;
        }
      },
      onDragEnter: () => {
        handleDragEnter(folder_element.dataset.drag_id);
      },
      onDragLeave: () => {
        handleDragLeave(folder_element.dataset.drag_id);
      },

      onDrop: (e) => {
        let item = e.source.element.dataset.drag_id;

        let drop_target = folder_element.dataset.drag_id;
        let drop_target_type = folder_element.dataset.item_type;
        let drop_target_parent_id = folder_element.dataset.parent_id;

        if (drop_target_type === "folder") {
          handleDrop(item, drop_target);
        } else {
          handleDrop(item, drop_target_parent_id);
        }
      },
    });
  });
}

class AutoSaver {
  room_id: string;
  doc: LoroDoc;
  hasChanges: boolean;
  intervalSeconds: number;
  constructor(room_id, doc, intervalSeconds = 300) {
    this.room_id = room_id;
    this.doc = doc;
    this.hasChanges = false;
    this.intervalSeconds = intervalSeconds;
    this.startAutoSave();
  }

  markChanged() {
    this.hasChanges = true;
  }

  async conditionalSave() {
    if (this.hasChanges === true) {
      // debounce(
      save_function(this.room_id, this.doc);
      // ,
      // )
      this.hasChanges = false;
    }
  }

  async startAutoSave() {
    setInterval(async () => {
      await this.conditionalSave();
    }, this.intervalSeconds * 1000);
  }
}

function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

export async function get_tree(doc: LoroDoc, room_id: string, on_tree) {
  let tree: LoroTree = doc.getTree("tree");
  // tree.enableFractionalIndex(0);
  // let root = tree.getNodeByID(ROOT_DOC_KEY);
  // root.data.set("name", "root");
  // root.data.set("item_type", "folder");

  // let folder1 = root.createNode();
  // folder1.data.set("name", "folder1");
  // folder1.data.set("item_type", "folder");

  // let folder2 = root.createNode();
  // folder2.data.set("name", "folder2");
  // folder2.data.set("item_type", "folder");

  // let file_1 = folder1.createNode();

  // file_1.data.set("name", "README.md");
  // file_1.data.set("item_type", "file");

  // let file_2 = folder2.createNode();

  // file_2.data.set("name", "gleam.toml");
  // file_2.data.set("item_type", "file");
  const autoSaver = new AutoSaver(room_id, doc);
  // Call
  doc.subscribe((e) => {
    let json = JSON.stringify(tree.toArray()[0]);
    on_tree(json);

    let snapshot = doc.export({ mode: "snapshot" });
    save_loro_doc(room_id, snapshot);

    autoSaver.markChanged();
  });
  autoSaver.startAutoSave();

  let json = JSON.stringify(tree.toArray()[0]);
  on_tree(json);

  await save_function(room_id, doc);
}

interface File {
  id: string; // room_id will be used as the primary key
  content: Uint8Array;
}

export async function create_loro_doc(room_id: string) {
  const db = new Dexie(room_id) as Dexie & {
    files: EntityTable<File, "id">;
  };

  // Schema declaration:
  db.version(1).stores({
    files: "id, content", // id is the primary key (room_id)
  });

  try {
    // Try to get existing document from Dexie using room_id
    const existingFile = await db.files.get(room_id);

    let doc: LoroDoc;
    if (existingFile && existingFile.content) {
      // const binaryString = atob(existingFile.content);
      // const snapshot = new Uint8Array(binaryString.length);
      // for (let i = 0; i < binaryString.length; i++) {
      //   snapshot[i] = binaryString.charCodeAt(i);
      // }

      doc = LoroDoc.fromSnapshot(existingFile.content);
      doc.setRecordTimestamp(true);
      return doc;
    } else {
      // Create new document with default content (a tree with a root document that dosen't have any children)
      let updateString =
        "bG9ybwAAAAAAAAAAAAAAALMgzjMAA9AAAABMT1JPAAHX7+veweqbzsQBBAACAHZ2Adfv697B6pvOxAEGAAwAxJxvVBva99cAAAAAAAMAAwEQAdf32htUb5zEAQEAAAAAAAUBAAABAAsCBAEDAAQEAAAAABQEbmFtZQlpdGVtX3R5cGUEdHJlZQkBAgIBAAMBAYAUAQQEBQACAAQEAAECBAEQBAsCBgEAEgAAAAEFBHJvb3QFBmZvbGRlcgAADAAdAAMAsImQGgEAAAAFAAAAAgBmcgAMAMScb1Qb2vfXAAAAADIPFQStAAAAogAAAExPUk8ABCJNGGBAgmIAAADxKwACAQAEdHJlZQQCCWl0ZW1fdHlwZQQGZm9sZGVyBG5hbWUEBHJvb3QAAdf32htUb5zEAAIAAQAGAIM2ACYDARkAQAQCAgFPABIFBwAFBgAgCQEZALADAQGAAAAANgACAAAAAACmP6p3AQAAAAUAAAANAADX99obVG+cxAAAAAABBgCDBHRyZWWhk7SsegAAAAAAAAA=";

      const binaryString = atob(updateString);
      const snapshot = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        snapshot[i] = binaryString.charCodeAt(i);
      }

      doc = LoroDoc.fromSnapshot(snapshot);
      doc.setRecordTimestamp(true);
      // Save the initial document to Dexie with room_id as the key
      await db.files.put({
        id: room_id,
        content: snapshot,
      });

      return doc;
    }
  } catch (error) {
    console.error("Error accessing Dexie database:", error);
    throw error;
  }
}

// Helper function to save document updates to Dexie
export async function save_loro_doc(room_id: string, snapshot: Uint8Array) {
  const db = new Dexie(room_id) as Dexie & {
    files: EntityTable<File, "id">;
  };

  db.version(1).stores({
    files: "id, content", // id is the primary key (room_id)
  });

  try {
    // const base64String = btoa(String.fromCharCode(...snapshot));

    // Update or create the file with room_id as the key
    await db.files.put({
      id: room_id,
      content: snapshot,
    });
  } catch (error) {
    console.error("Error saving to Dexie database:", error);
    throw error;
  }
}

export function create_new_note(doc: LoroDoc, item_id) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let note = tree.createNode(item_id);
    note.data.set("item_type", "file");
    // note.data.set("name", "Untitled");

    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function create_new_folder(doc: LoroDoc, item_id) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let folder = tree.createNode(item_id);
    folder.data.set("item_type", "folder");
    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function move_item(
  doc: LoroDoc,
  item_id: TreeID,
  drop_target_id: TreeID
) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    tree.move(item_id, drop_target_id);

    doc.commit();
  } catch (error) {
    console.log("Move failed", error);
  }
}

export function delete_item(doc: LoroDoc, item_id: TreeID) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    tree.delete(item_id);

    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function change_item_name(
  doc: LoroDoc,
  item_id: TreeID,
  item_name: String,
  item_name_changed
) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let item_node = tree.getNodeByID(item_id);

    if (item_node) {
      item_node.data.set("name", item_name);

      doc.commit();

      item_name_changed();
    } else {
      throw console.error();
    }
  } catch (error) {
    item_name_changed();
    console.log("Delete failed", error);
  }
}
