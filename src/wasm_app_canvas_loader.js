const wasm_module_path = "bin/wasm_app.wasm";
const canvas_id = "wasm_app_canvas";

// > The `WebAssembly.Memory` object is a resizable `ArrayBuffer` or `SharedArrayBuffer`
// > that holds the raw bytes of memory accessed by a `WebAssembly.Instance`. Both WebAssembly
// > and JavaScript can create Memory objects. If you want to access the memory created in
// > JS from Wasm or vice versa, you can pass a reference to the memory from one side to the other.
let memory = new WebAssembly.Memory({
    initial: 200 /* pages (64kb per page) */, 
    maximum: 200 /* pages (64kb per page) */, 
});

// This buffer contains all the memory being used by the wasm module.
// This means that a pointer inside the module is basically an offset in this buffer.
const wasm_memory_viewer = new DataView(memory.buffer);
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8");

let temp_file = "";
let things_available_to_the_wasm_module = {
    
    env: {
        
        memory: memory,
        
        // pub extern fn js_console_log(str: [*]const u8, len: usize) void;
        js_console_log: (str_ptr, len) => {
            const str = decoder.decode(memory.buffer.slice(str_ptr, str_ptr+len));
            console.log("WASM: ", str);
        },
        
        // pub extern fn js_milli_since_epoch() usize;
        js_milli_since_epoch: () => {
            return Date.now()
        },

        // pub extern fn js_read_file_synch(file_name_ptr: [*]const u8, file_name_len: usize, out_ptr: [*]const u8, out_size: *usize) void;
        js_read_file_synch: (file_name_ptr, file_name_len, out_ptr_ptr, out_size_ptr) => {
            const file_name_str = decoder.decode(memory.buffer.slice(file_name_ptr, file_name_ptr+file_name_len));
            console.log("JS: read file synch", file_name_str);
            
            // NOTE I use `XMLHttpRequest` rather than `fetch` because I want to read the file in a synchronous way
            const xhr = new XMLHttpRequest();
            // NOTE This is literally a hack so that bytes come through un-processed, because aparently, web developers CANT be trusted dealing with bytes or who knows why....
            xhr.overrideMimeType('text/plain; charset=x-user-defined');
            xhr.open('GET', file_name_str, false);
            xhr.send(null);
            // NOTE someone decided that synchronous requests cant use the `responseType` property ffs...
            // 
            //     xhr.responseType = 'arraybuffer'; // using this we could have just gotten the bytes directly
            // 
            // So instead we need to hack around that bullshit and write some terribly looking code to just get a damn byte array......
            const binary_string = xhr.responseText;
            const length = binary_string.length;
            let data = new Uint8Array(length);
            for (let i = 0; i < length; i++) {
                const byte = binary_string.charCodeAt(i) & 0xff;
                data.set([byte], i);
            }

            const file_content_length = length;
            const allocated_buffer = window.instance.exports.wasm_request_buffer(file_content_length);
            new Uint8Array(memory.buffer, allocated_buffer, file_content_length).set(data);
            new Uint32Array(memory.buffer, out_ptr_ptr, 1).set([allocated_buffer]);
            new Uint32Array(memory.buffer, out_size_ptr, 1).set([file_content_length]);
        },

        js_read_file_asynch: (file_name_ptr, file_name_len) => {
            const file_name_str = decoder.decode(memory.buffer.slice(file_name_ptr, file_name_ptr+file_name_len));
            console.log("INFO: fetch", file_name_str, "request from wasm module...")
            fetch(file_name_str).then(r => r.arrayBuffer()).then(buffer => {
                const ptr = window.instance.exports.wasm_request_buffer(buffer.byteLength);
                new Uint8Array(memory.buffer).set(new Uint8Array(buffer), ptr);
                const event = "buffer:" + file_name_str;
                const interface_buffer_ptr = window.instance.exports.wasm_get_static_buffer();
                new Uint8Array(memory.buffer).set(encoder.encode(event), interface_buffer_ptr);
                window.instance.exports.wasm_send_event(event.length, ptr, buffer.byteLength);
            });
        },

    },
};

// keyboard input stuff
let keys = Array(256).fill(false);
window.addEventListener("keydown", (e)=> {
    const char = e.key.charCodeAt(0) - 32;
    const is_valid_key = char >= 0 && char < 256;
    if (!is_valid_key) return;
    keys[char] = true;
});
window.addEventListener("keyup", (e)=> {
    const char = e.key.charCodeAt(0) - 32;
    const is_valid_key = char >= 0 && char < 256;
    if (!is_valid_key) return;
    keys[char] = false;
});

// mouse input stuff
let mouse_down = 0;
let mouse_position = { x: undefined, y: undefined };
window.addEventListener('mouseup', (e) => {
    mouse_down = 0;
});
window.addEventListener('mousedown', (e) => {
    mouse_down = 1;
    if (window.instance != undefined) {
        const interface_buffer_ptr = wasm_get_static_buffer();
        const message = "mouse:down";
        new Uint8Array(memory.buffer).set(encoder.encode(message), interface_buffer_ptr);
        window.instance.wasm_send_event(message.length, 0, 0);
    }
});
window.addEventListener('mousemove', (e) => {
    mouse_position = { x: e.clientX, y: e.clientY };
});

// > `instantiateStreaming` compiles and instantiates a WebAssembly module directly from a
// > streamed underlying source. This is the most efficient, optimized way to load Wasm code.
WebAssembly.instantiateStreaming(fetch(wasm_module_path), things_available_to_the_wasm_module).then((result) => {
    
    console.log("INFO: object `result.instance.exports`: ");
    console.log(result.instance.exports);

    window.instance = result.instance;
    
    // These are the functions provided byt the module
    const wasm_get_canvas_pixels = result.instance.exports.wasm_get_canvas_pixels;
    const wasm_get_canvas_size = result.instance.exports.wasm_get_canvas_size;
    const wasm_get_canvas_scaling = result.instance.exports.wasm_get_canvas_scaling;
    const wasm_tick = result.instance.exports.wasm_tick;
    const wasm_init = result.instance.exports.wasm_init;
    const wasm_send_event = result.instance.exports.wasm_send_event;
    const wasm_request_buffer = result.instance.exports.wasm_request_buffer;
    const wasm_get_static_buffer = result.instance.exports.wasm_get_static_buffer;
    const wasm_set_mouse = result.instance.exports.wasm_set_mouse;
    const wasm_set_dt = result.instance.exports.wasm_set_dt;

    // This is the 256 bytes buffer used to interface js code and wasm code
    const interface_buffer_ptr = wasm_get_static_buffer();

    wasm_init();
    wasm_get_canvas_size(interface_buffer_ptr, interface_buffer_ptr+4);
    const scale_value = wasm_get_canvas_scaling();
    const canvas_size = {
        w: wasm_memory_viewer.getUint32(interface_buffer_ptr, true),
        h: wasm_memory_viewer.getUint32(interface_buffer_ptr+4, true)
    };
    console.log("INFO: canvas size:", canvas_size);
    const canvas = document.getElementById(canvas_id);
    canvas.width = canvas_size.w;
    canvas.height = canvas_size.h;
    canvas.style.transform = "translate("+(50*(scale_value-1))+"%,"+(50*(scale_value-1))+"%) scale("+scale_value+","+(-scale_value)+")";
    const canvas_context = canvas.getContext("2d");
    const canvas_pixel_data = canvas_context.createImageData(canvas.width, canvas.height);
    canvas_context.clearRect(0, 0, canvas.width, canvas.height);
    const canvas_pixel_size = 4;

    let timestamp_previous = performance.now();
    const tick_interval_seconds = 1/60;
    setInterval(
        () => {
            wasm_set_mouse(mouse_position.x, mouse_position.y, mouse_down);
            new Uint8Array(memory.buffer).set(keys, interface_buffer_ptr);
            const timestamp_now = performance.now();
            wasm_set_dt(timestamp_now - timestamp_previous);
            wasm_tick();
            timestamp_previous = timestamp_now;
            
            const pixel_data_offset = wasm_get_canvas_pixels();
            const module_pixel_data = new Uint8Array(memory.buffer).slice(
                pixel_data_offset,
                pixel_data_offset + (canvas.width * canvas.height * canvas_pixel_size)
            );

            canvas_pixel_data.data.set(module_pixel_data);
            canvas_context.putImageData(canvas_pixel_data, 0, 0);
        },
        tick_interval_seconds * 1000
    );
});
