main();

function main() {
  const canvas = document.querySelector("#dvui-canvas");
  // Initialize the GL context
  const gl = canvas.getContext("webgl2");

  // Only continue if WebGL is available and working
  if (gl === null) {
    alert("Unable to initialize WebGL. Your browser or machine may not support it.");
    return;
  }

  // Vertex shader
  const vsSource = `# version 300 es

    precision mediump float;

    in vec4 aVertexPosition;
    in vec4 aVertexColor;
    in vec2 aTextureCoord;

    uniform mat4 uMatrix;

    out vec4 vColor;
    out vec2 vTextureCoord;

    void main() {
      gl_Position = uMatrix * aVertexPosition;
      vColor = aVertexColor;
      vTextureCoord = aTextureCoord;
    }
  `;

  // Fragment shader
  const fsSource = `# version 300 es

    precision mediump float;

    in vec4 vColor;
    in vec2 vTextureCoord;

    uniform sampler2D uSampler;
    uniform bool useTex;

    out vec4 fragColor;

    void main() {
        if (useTex) {
            fragColor = texture(uSampler, vTextureCoord);
        }
        else {
            fragColor = vColor;
        }
    }
  `;

  const vertexShader = gl.createShader(gl.VERTEX_SHADER);
  gl.shaderSource(vertexShader, vsSource);
  gl.compileShader(vertexShader);
  if (!gl.getShaderParameter(vertexShader, gl.COMPILE_STATUS)) {
    alert(`Error compiling vertex shader: ${gl.getShaderInfoLog(shader)}`);
    gl.deleteShader(vertexShader);
    return null;
  }

  const fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fragmentShader, fsSource);
  gl.compileShader(fragmentShader);
  if (!gl.getShaderParameter(fragmentShader, gl.COMPILE_STATUS)) {
    alert(`Error compiling fragment shader: ${gl.getShaderInfoLog(shader)}`);
    gl.deleteShader(fragmentShader);
    return null;
  }

  const shaderProgram = gl.createProgram();
  gl.attachShader(shaderProgram, vertexShader);
  gl.attachShader(shaderProgram, fragmentShader);
  gl.linkProgram(shaderProgram);

  if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
    alert(`Error initializing shader program: ${gl.getProgramInfoLog(shaderProgram)}`);
    return null;
  }

    const programInfo = {
      program: shaderProgram,
      attribLocations: {
        vertexPosition: gl.getAttribLocation(shaderProgram, "aVertexPosition"),
        vertexColor: gl.getAttribLocation(shaderProgram, "aVertexColor"),
        textureCoord: gl.getAttribLocation(shaderProgram, "aTextureCoord"),
      },
      uniformLocations: {
        matrix: gl.getUniformLocation(shaderProgram, "uMatrix"),
        uSampler: gl.getUniformLocation(shaderProgram, "uSampler"),
        useTex: gl.getUniformLocation(shaderProgram, "useTex"),
      },
    };

  const positionBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
  const positions = [100, 100, 200, 100, 200, 200, 100, 200];
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);

  const colorBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, colorBuffer);
  const colors = [
      1.0, 1.0, 1.0, 1.0, // white
      1.0, 0.0, 0.0, 1.0, // red
      0.0, 1.0, 0.0, 1.0, // green
      0.0, 0.0, 1.0, 1.0, // blue
  ];
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(colors), gl.STATIC_DRAW);

  const textureCoordBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, textureCoordBuffer);
  const textureCoordinates = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
  gl.bufferData( gl.ARRAY_BUFFER, new Float32Array(textureCoordinates), gl.STATIC_DRAW);

  const indexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
  const indices = [ 0, 1, 2, 0, 2, 3];
  gl.bufferData( gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(indices), gl.STATIC_DRAW);

  const vertexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
  const vertexes = [
      100, 150, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0,
      200, 150, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0,
      200, 250, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0,
      100, 250, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0,
    ];
  gl.bufferData( gl.ARRAY_BUFFER, new Float32Array(vertexes), gl.STATIC_DRAW);

    const buffers = {
        position: positionBuffer,
        color: colorBuffer,
        textureCoord: textureCoordBuffer,
        indices: indexBuffer,
        vertices: vertexBuffer,
    };

    const texture = loadTexture(gl, "cubetexture.png");
    //const texture = loadTexture(gl, "webgl.png");
    // Flip image pixels into the bottom-to-top order that WebGL expects.
    //gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);

    function render() {
        drawScene(gl, programInfo, buffers, texture);
        requestAnimationFrame(render);
    }

    requestAnimationFrame(render);
}



function drawScene(gl, programInfo, buffers, texture) {
  gl.clearColor(0.0, 0.0, 0.0, 1.0); // Clear to black, fully opaque
  gl.clearDepth(1.0); // Clear everything
  gl.enable(gl.DEPTH_TEST); // Enable depth testing
  gl.depthFunc(gl.LEQUAL); // Near things obscure far things

  // Clear the canvas before we start drawing on it.

  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

  let matrix = new Float32Array(16);
  matrix[0] = 2.0 / gl.canvas.clientWidth;
  matrix[1] = 0.0;
  matrix[2] = 0.0;
  matrix[3] = 0.0;
  matrix[4] = 0.0;
  matrix[5] = -2.0 / gl.canvas.clientHeight;
  matrix[6] = 0.0;
  matrix[7] = 0.0;
  matrix[8] = 0.0;
  matrix[9] = 0.0;
  matrix[10] = 1.0;
  matrix[11] = 0.0;
  matrix[12] = -1.0;
  matrix[13] = 1.0;
  matrix[14] = 0.0;
  matrix[15] = 1.0;

  // vertex
  gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vertices);
  gl.vertexAttribPointer(
    programInfo.attribLocations.vertexPosition,
    2,  // num components
    gl.FLOAT,
    false,  // don't normalize
    32,  // stride
    0,  // offset
  );
  gl.enableVertexAttribArray(programInfo.attribLocations.vertexPosition);

  // color
  gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vertices);
  gl.vertexAttribPointer(
    programInfo.attribLocations.vertexColor,
    4,  // num components
    gl.FLOAT,
    false,  // don't normalize
    32, // stride
    8,  // offset
  );
  gl.enableVertexAttribArray(programInfo.attribLocations.vertexColor);

  // texture
  gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vertices);
  gl.vertexAttribPointer(
    programInfo.attribLocations.textureCoord,
    2,  // num components
    gl.FLOAT,
    false,  // don't normalize
    32, // stride
    24,  // offset
  );
  gl.enableVertexAttribArray(programInfo.attribLocations.textureCoord);

  // Tell WebGL to use our program when drawing
  gl.useProgram(programInfo.program);

  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.indices);

  // Set the shader uniforms
  gl.uniformMatrix4fv(
    programInfo.uniformLocations.matrix,
    false,
    matrix,
  );

    gl.activeTexture(gl.TEXTURE0);

    // Bind the texture to texture unit 0
    gl.bindTexture(gl.TEXTURE_2D, texture);

    // Tell the shader we bound the texture to texture unit 0
    gl.uniform1i(programInfo.uniformLocations.uSampler, 0);

    gl.uniform1i(programInfo.uniformLocations.useTex, 1);

    const vertexCount = 6;
    const type = gl.UNSIGNED_SHORT;
    const offset = 0;
    gl.drawElements(gl.TRIANGLES, vertexCount, type, offset);
}

function loadTexture(gl, url) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);

  // Because images have to be downloaded over the internet
  // they might take a moment until they are ready.
  // Until then put a single pixel in the texture so we can
  // use it immediately. When the image has finished downloading
  // we'll update the texture with the contents of the image.
  const level = 0;
  const internalFormat = gl.RGBA;
  const width = 1;
  const height = 1;
  const border = 0;
  const srcFormat = gl.RGBA;
  const srcType = gl.UNSIGNED_BYTE;
  const pixel = new Uint8Array([0, 0, 255, 255]); // opaque blue
  gl.texImage2D(
    gl.TEXTURE_2D,
    level,
    internalFormat,
    width,
    height,
    border,
    srcFormat,
    srcType,
    pixel,
  );

  const image = new Image();
  image.onload = () => {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(
      gl.TEXTURE_2D,
      level,
      internalFormat,
      srcFormat,
      srcType,
      image,
    );

    // WebGL1 has different requirements for power of 2 images
    // vs. non power of 2 images so check if the image is a
    // power of 2 in both dimensions.
    if (isPowerOf2(image.width) && isPowerOf2(image.height)) {
      // Yes, it's a power of 2. Generate mips.
      gl.generateMipmap(gl.TEXTURE_2D);
        //alert("pow2");
    } else {
      // No, it's not a power of 2. Turn off mips and set
      // wrapping to clamp to edge
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    }
  };
  image.src = url;

  return texture;
}

function isPowerOf2(value) {
  return (value & (value - 1)) === 0;
}

