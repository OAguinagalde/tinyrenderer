// > The `WebAssembly.Memory` object is a resizable `ArrayBuffer` or `SharedArrayBuffer`
// > that holds the raw bytes of memory accessed by a `WebAssembly.Instance`. Both WebAssembly
// > and JavaScript can create Memory objects. If you want to access the memory created in
// > JS from Wasm or vice versa, you can pass a reference to the memory from one side to the other.
let memory = new WebAssembly.Memory({
    initial: 2 /* pages */,
    maximum: 2 /* pages */,
});

// This contains everything that the wasm module will have access to
let importObject = {
    env: {
        consoleLog: (arg) => console.log(arg),
        memory: memory,
    },
};

const wasm_module_path = "lib/wasm_app.wasm";
const canvas_id = "wasm_app_canvas";
// > `instantiateStreaming` compiles and instantiates a WebAssembly module directly from a
// > streamed underlying source. This is the most efficient, optimized way to load Wasm code.
WebAssembly.instantiateStreaming(fetch(wasm_module_path), importObject).then((result) => {
    
    // This buffer contains all the memory being used by the wasm module.
    // This means that a pointer inside the module is basically an offset in this buffer.
    const wasmMemoryArray = new Uint8Array(memory.buffer);
    const wasmMemoryViewer = new DataView(memory.buffer);

    console.log("[INFO] object `result.instance.exports`: ");
    console.log(result.instance.exports);
    
    // These are the functions provided byt the module
    const wasm_get_pixel_buffer_ptr = result.instance.exports.wasm_get_pixel_buffer_ptr;
    const wasm_get_canvas_size = result.instance.exports.wasm_get_canvas_size;
    const wasm_tick = result.instance.exports.wasm_tick;
    
    // This is the 256 bytes buffer used to interface js code and wasm code
    const interface_buffer_ptr = result.instance.exports.wasm_get_interface_buffer();
    
    wasm_get_canvas_size(interface_buffer_ptr, interface_buffer_ptr+4);
    const canvasSize = {
        w: wasmMemoryViewer.getUint32(interface_buffer_ptr, true),
        h: wasmMemoryViewer.getUint32(interface_buffer_ptr+4, true)
    };
    console.log("[INFO] canvas size:");
    console.log(canvasSize);

    const canvas = document.getElementById(canvas_id);
    canvas.width = canvasSize.w;
    canvas.height = canvasSize.h;
    // the actual pixels of the canvas 
    const canvas_context = canvas.getContext("2d");
    const canvas_pixel_data = canvas_context.createImageData(canvas.width, canvas.height);
    canvas_context.clearRect(0, 0, canvas.width, canvas.height);
    const canvas_pixel_size = 4;

    const tick_interval = 1/60;
    setInterval(
        () => {
            wasm_tick();
            
            const pixel_data_offset = wasm_get_pixel_buffer_ptr();
            const module_pixel_data = wasmMemoryArray.slice(
                pixel_data_offset,
                pixel_data_offset + (canvas.width * canvas.height * canvas_pixel_size)
            );

            canvas_pixel_data.data.set(module_pixel_data);
            canvas_context.putImageData(canvas_pixel_data, 0, 0);
        },
        tick_interval
    );
});
