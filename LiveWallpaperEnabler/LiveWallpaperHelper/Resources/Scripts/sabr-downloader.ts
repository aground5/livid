// sabr-downloader.ts
// Ported from LuanRT/googlevideo examples

import { parse } from "https://deno.land/std@0.220.0/flags/mod.ts";
import { Innertube, UniversalCache, YTNodes, Constants, Platform, IPlayerResponse } from "npm:youtubei.js@^12.0.0";
import { BG, type BgConfig } from "npm:bgutils-js@^2.0.0";
import { JSDOM } from "npm:jsdom@^24.0.0";

import { SabrStream, type SabrPlaybackOptions } from "jsr:@luanrt/googlevideo/sabr-stream";
import { type SabrFormat } from "jsr:@luanrt/googlevideo/shared-types";
import { buildSabrFormat } from "jsr:@luanrt/googlevideo/utils";

// --- WebPO Helper Logic ---
async function generateWebPoToken(contentBinding: string) {
    const requestKey = 'O43z0dpjhgX20SCx4KAo';
    if (!contentBinding) throw new Error('Could not get visitor data');

    const dom = new JSDOM();

    // Basic polyfills for bgutils
    const globalAny = globalThis as any;
    globalAny.window = dom.window;
    globalAny.document = dom.window.document;

    const bgConfig: BgConfig = {
        fetch: (input: any, init?: any) => fetch(input, init),
        globalObj: globalThis,
        identifier: contentBinding,
        requestKey
    };

    const bgChallenge = await BG.Challenge.create(bgConfig);
    if (!bgChallenge) throw new Error('Could not get challenge');

    const interpreterJavascript = bgChallenge.interpreterJavascript.privateDoNotAccessOrElseSafeScriptWrappedValue;
    if (interpreterJavascript) {
        new Function(interpreterJavascript)();
    } else throw new Error('Could not load VM');

    const poTokenResult = await BG.PoToken.generate({
        program: bgChallenge.program,
        globalName: bgChallenge.globalName,
        bgConfig
    });

    return { poToken: poTokenResult.poToken };
}

// --- Player Request Logic ---
// Fix for youtubei.js build script execution in Deno
Platform.shim.eval = async (data: any, env: any) => {
    // Simplified eval shim
    return new Function("return " + data.output)();
    // Note: The original generic shim might be safer, but let's try simple first
};

async function makePlayerRequest(innertube: Innertube, videoId: string, reloadPlaybackContext?: any): Promise<IPlayerResponse> {
    const watchEndpoint = new YTNodes.NavigationEndpoint({ watchEndpoint: { videoId } });

    const extraArgs: any = {
        playbackContext: {
            adPlaybackContext: { pyv: true },
            contentPlaybackContext: {
                vis: 0,
                splay: false,
                lactMilliseconds: '-1',
                signatureTimestamp: innertube.session.player?.signature_timestamp
            }
        },
        contentCheckOk: true,
        racyCheckOk: true
    };

    if (reloadPlaybackContext) {
        extraArgs.playbackContext.reloadPlaybackContext = reloadPlaybackContext;
    }

    return await watchEndpoint.call(innertube.actions, { ...extraArgs, parse: true });
}

// --- Main Download Logic ---
async function downloadVideo(videoId: string, startOutput: string) {
    console.log(`[Deno] Initializing Innertube...`);
    const innertube = await Innertube.create({ cache: new UniversalCache(true) });

    let poToken: string | undefined;
    let clientName = 1; // WEB

    console.log(`[Deno] Generating PO Token...`);
    try {
        const webPoTokenResult = await generateWebPoToken(videoId);
        poToken = webPoTokenResult.poToken;
        console.log(`[Deno] PO Token generated successfully.`);
    } catch (e) {
        console.warn(`[Deno] PO Token generation failed. Fallback to Android client (no token). Error: ${e}`);
        clientName = 3; // ANDROID
    }

    console.log(`[Deno] Fetching player response...`);
    const playerResponse = await makePlayerRequest(innertube, videoId);

    const videoTitle = playerResponse.video_details?.title || 'Unknown';
    console.log(`[Deno] Title: ${videoTitle}`);

    // Sabr Setup
    const serverAbrStreamingUrl = await innertube.session.player?.decipher(playerResponse.streaming_data?.server_abr_streaming_url);
    const videoPlaybackUstreamerConfig = playerResponse.player_config?.media_common_config.media_ustreamer_request_config?.video_playback_ustreamer_config;

    if (!videoPlaybackUstreamerConfig || !serverAbrStreamingUrl) {
        throw new Error("SABR streaming info not found. This video might not support SABR or needs premium.");
    }

    const sabrFormats = playerResponse.streaming_data?.adaptive_formats.map(buildSabrFormat) || [];

    const serverAbrStream = new SabrStream({
        formats: sabrFormats,
        serverAbrStreamingUrl,
        videoPlaybackUstreamerConfig,
        poToken: poToken,
        clientInfo: {
            clientName: clientName,
            clientVersion: innertube.session.context.client.clientVersion
        }
    });

    // Also update Innertube client context if we switched to Android
    if (clientName === 3) {
        innertube.session.context.client.clientName = 'ANDROID';
        innertube.session.context.client.clientVersion = Constants.CLIENTS.ANDROID.VERSION;
    }

    const options: SabrPlaybackOptions = {
        preferWebM: true,
        videoQuality: '2160p', // Target 4K
        audioQuality: 'AUDIO_QUALITY_MEDIUM',
        // enabledTrackTypes: EnabledTrackTypes.VIDEO_AND_AUDIO (Need to import this enum or use string)
        enabledTrackTypes: 3 // VIDEO_AND_AUDIO
    };

    console.log(`[Deno] Starting SABR stream...`);
    const { videoStream, audioStream, selectedFormats } = await serverAbrStream.start(options);

    console.log(`[Deno] Selected Video: ${selectedFormats.videoFormat.qualityLabel} (${selectedFormats.videoFormat.width}x${selectedFormats.videoFormat.height})`);

    // Write streams to file
    // For simplicity in this PoC, we only write video to the output path
    // In reality, we need to merge audio/video or output two files

    // Let's write video only for now to verify 4K download
    const videoFile = await Deno.open(startOutput, { write: true, create: true });

    console.log(`[Deno] Downloading video to ${startOutput}...`);
    // Pipe ReadableStream to Deno File
    const reader = videoStream.getReader();
    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        await videoFile.write(value);
    }

    videoFile.close();
    console.log(`[Deno] Download Complete!`);
}

async function main() {
    const args = parse(Deno.args);
    const url = args._[0] as string;
    const output = args.output || "output.webm";

    if (!url) {
        console.error("Usage: sabr-downloader.ts <url> --output <path>");
        Deno.exit(1);
    }

    // Extract ID
    const videoIdMatch = url.match(/(?:v=|\/)([0-9A-Za-z_-]{11})/);
    const videoId = videoIdMatch ? videoIdMatch[1] : url;

    try {
        await downloadVideo(videoId, output);
    } catch (e) {
        console.error("[Deno] Error:", e);
        Deno.exit(1);
    }
}

if (import.meta.main) {
    await main();
}
