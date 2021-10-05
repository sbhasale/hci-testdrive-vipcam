require('dotenv').config();
const multer = require('multer');
const express = require('express');
const expressApp = express();
const httpServer = require('http').Server(expressApp);
const io = require('socket.io')(httpServer);
const path = require('path');
const fs = require('fs');
const Pipeline = require('./scripts/pipeline');

const connectionString = process.env.IOTHUB_CONNECTION_STRING;
const deviceId = process.env.DEVICE_NAME;
const port = process.env.PORT || '3000';

class App {
    constructor() {
        this.pipeline = new Pipeline(connectionString, deviceId);
        
        io.on('connection', (socket) => {
            console.log('a user connected');
            socket.on('get zones', (msg) => {
                console.log(`get zones: ${msg}`);
                this.getZones();
            });
            socket.on('set zones', (msg) => {
                console.log(`set zones: ${msg}`);
                this.setZones(msg);
            });
            socket.on('get videos', (msg) => {
                console.log(`get videos: ${msg}`);
                this.getVideos();
            });
            socket.on('get settings', (msg) => {
                fs.readFile("./settings.json", (err, data) => {
                    if (err) {
                        console.log(`get settings error: ${err}`);
                    } else {
                        const settings = JSON.parse(data);
                        io.emit('settings', JSON.stringify({
                            avaPlayer: {
                                clientApiEndpointUrl: process.env.CLIENT_API_ENDPOINT_URL,
                                videoName: settings.videoName,
                                token: process.env.JWT_TOKEN
                            }
                        }));
                    }
                });
            });
            socket.on('set video', (msg) => {
                console.log(`set video: ${msg}`);
                this.setVideo(msg);
            });
            socket.on('disconnect', () => {
                console.log('user disconnected');
            });
        });
        
        httpServer.listen(port, () => {
            console.log(`listening on *:${port}`);
        });
        
        expressApp.use(express.static('videos'));
        expressApp.use(express.static('scripts'));
        
        expressApp.get('/', (req, res) => {
            res.sendFile(path.join(__dirname, 'index.html'));
        });
        expressApp.post('/uploadVideo', multer({
            storage: multer.diskStorage({
                destination: 'videos', // Destination to store video 
                filename: (req, file, cb) => {
                    cb(null, file.fieldname + '_' + Date.now()
                        + path.extname(file.originalname))
                }
            }),
            limits: {
                fileSize: 1000000000 // 10000000 Bytes = 1000 MB
            },
            fileFilter(req, file, cb) {
                // upload only mp4 and mkv format
                if (!file.originalname.match(/\.(mkv)$/)) {
                    return cb(new Error('Please upload a video'))
                }
                cb(undefined, true)
            }
        }).single('video'), (req, res) => {
            res.send(req.file);
            this.getVideos();
        }, (error, req, res, next) => {
            console.log(error);
            res.status(400).send({ error: error.message })
        });
    }

    getVideos() {
        fs.readdir(path.join(__dirname, 'videos'), (err, files) => {
            if (err) {
                console.log(err);
            } else {
                io.emit('videos', JSON.stringify(files.filter((file) => {
                    return path.extname(file) === '.mkv';
                })))
            }
        });
    }

    async setVideo(url) {
        const path = url.split('/');
        const name = path[path.length - 1];
        const title = name.split('.')[0].replace('_', '');
    
        const succeeded = await this.pipeline.setVideo(url, name, title);
    
        if (succeeded) {
            const settings = {
                videoName: title
            };
            fs.writeFile("./settings.json", JSON.stringify(settings), (err) => {
                if (err) {
                    console.log(`settings update error: ${err}`);
                } else {
                    console.log(`settings updated: ${settings}`);
                    io.emit('get settings', '');
                }
            });
        }
    }

    getZones() {
        const zones = [];
        // TODO: get zones from pipeline if doesn't exist
        fs.readFile("./zones.json", (err, data) => {
            if (err) {
                console.log(`get settings error: ${err}`);
            } else {
                const zones = JSON.parse(data);
                io.emit('zones', JSON.stringify(zones));
            }
        });
    }

    async setZones(zones) {
        const succeeded = await this.pipeline.setZones(JSON.parse(zones));

        if (succeeded) {
            fs.writeFile("./zones.json", zones, (err) => {
                if (err) {
                    console.log(`zones update error: ${err}`);
                } else {
                    console.log(`zones updated: ${zones}`);
                    io.emit('get zones', '');
                }
            });
        }
    }
}

new App();