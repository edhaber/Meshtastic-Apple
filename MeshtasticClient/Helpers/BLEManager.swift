import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
    let id: String
    let index: Int
    let name: String
    let rssi: Int
}

//---------------------------------------------------------------------------------------
// Meshtastic BLE Device Manager
//---------------------------------------------------------------------------------------
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // Data
    private var centralManager: CBCentralManager!
    @Published var connectedPeripheral: CBPeripheral!
    @Published var peripheralArray = [CBPeripheral]()
    private var rssiArray = [NSNumber]()
    private var timer = Timer()
    
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    
    var TORADIO_characteristic: CBCharacteristic!
    var FROMRADIO_characteristic: CBCharacteristic!
    var FROMNUM_characteristic: CBCharacteristic!
    
    let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
    let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
    let FROMRADIO_UUID = CBUUID(string: "0x8BA2BCC2-EE02-4A55-A531-C525C5E454D5")
    let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453") //Notify
    
    override init() {
        super.init()
 
        centralManager = CBCentralManager(delegate: self, queue: nil)
        centralManager.delegate = self
        
    }

    //---------------------------------------------------------------------------------------
    // Check for Bluetooth Connectivity
    //---------------------------------------------------------------------------------------
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
         if central.state == .poweredOn {
             isSwitchedOn = true
         }
         else {
             isSwitchedOn = false
         }
    }
    
    //---------------------------------------------------------------------------------------
    // Scan for nearby BLE devices using the Meshtastic BLE service ID
    //---------------------------------------------------------------------------------------
    func startScanning() {
        // Remove Existing Data
        peripherals.removeAll()
        peripheralArray.removeAll()
        rssiArray.removeAll()
        // Start Scanning
        print("Start Scanning")
        centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID])
    }
        
    //---------------------------------------------------------------------------------------
    // Stop Scanning For BLE Devices
    //---------------------------------------------------------------------------------------
    func stopScanning() {
        print("Stop Scanning")
        self.centralManager.stopScan()
    }
    
    //---------------------------------------------------------------------------------------
    // Connect to a Device via UUID
    //---------------------------------------------------------------------------------------
    func connectToDevice(id: String) {
        connectedPeripheral = peripheralArray.filter({ $0.identifier.uuidString == id }).first
        self.centralManager?.connect(connectedPeripheral!)
    }
    
    //---------------------------------------------------------------------------------------
    // Disconnect Device function
    //---------------------------------------------------------------------------------------
    func disconnectDevice(){
        if connectedPeripheral != nil {
            self.centralManager?.cancelPeripheralConnection(connectedPeripheral!)
        }
    }
    
    //---------------------------------------------------------------------------------------
    // Discover Peripheral Event
    //---------------------------------------------------------------------------------------
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        //print(peripheral)
        if peripheralArray.contains(peripheral) {
          print("Duplicate Found.")
        } else {
            print("Adding peripheral: " + peripheral.name!);
            peripheralArray.append(peripheral)
            rssiArray.append(RSSI)
        }
       
        var peripheralName: String!
        peripheralName = peripheral.name
        if peripheral.name == nil {
            if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                peripheralName = name
            }
            else {
                peripheralName = "Unknown"
            }
        }

        let newPeripheral = Peripheral(id: peripheral.identifier.uuidString, index: peripherals.count, name: peripheralName, rssi: RSSI.intValue)
        //print(newPeripheral)
        peripherals.append(newPeripheral)
    }
    
    //---------------------------------------------------------------------------------------
    // Connect Peripheral Event
    //---------------------------------------------------------------------------------------
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Peripheral connected: " + peripheral.name!)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        self.startScanning()
    }
    
    //---------------------------------------------------------------------------------------
    // Disconnect Peripheral Event
    //---------------------------------------------------------------------------------------
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        if(peripheral.identifier == connectedPeripheral.identifier){
            connectedPeripheral = nil
        }
        print("Peripheral disconnected: " + peripheral.name!)
        self.startScanning()
    }
    
    //---------------------------------------------------------------------------------------
    // Discover Services Event
    //---------------------------------------------------------------------------------------
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        guard let services = peripheral.services else { return }
                
        for service in services
        {
            print("Service discovered: " + service.uuid.uuidString)
            
            if (service.uuid == meshtasticServiceCBUUID)
            {
                print ("Meshtastic service OK")
                
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    //---------------------------------------------------------------------------------------
    // Discover Characteristics Event
    //---------------------------------------------------------------------------------------
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
      guard let characteristics = service.characteristics else { return }

      for characteristic in characteristics {
        
        switch characteristic.uuid
        {
            case TORADIO_UUID:
                print("TORADIO characteristic OK")
                TORADIO_characteristic = characteristic
                var toRadio: ToRadio = ToRadio()
                toRadio.wantConfigID = 32168
                let binaryData: Data = try! toRadio.serializedData()
                peripheral.writeValue(binaryData, for: characteristic, type: .withResponse)
                break
            
            case FROMRADIO_UUID:
                print("FROMRADIO characteristic OK")
                FROMRADIO_characteristic = characteristic
                peripheral.readValue(for: FROMRADIO_characteristic)
                break
            
            case FROMNUM_UUID:
                print("FROMNUM (Notify) characteristic OK")
                FROMNUM_characteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                break
            
            default:
                break
        }
        
      }
    }
    
    //---------------------------------------------------------------------------------------
    // Data Read / Update Characteristic Event
    //---------------------------------------------------------------------------------------
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        switch characteristic.uuid
        {
            case FROMNUM_UUID:
                peripheral.readValue(for: FROMRADIO_characteristic)
                
            case FROMRADIO_UUID:
                if (characteristic.value == nil || characteristic.value!.isEmpty)
                {
                    return
                }
                //print(characteristic.value ?? "no value")
                //let byteArray = [UInt8](characteristic.value!)
                //print(characteristic.value?.hexDescription ?? "no value")
                var decodedInfo = FromRadio()
                
                decodedInfo = try! FromRadio(serializedData: characteristic.value!)
                //print(decodedInfo.myInfo.myNodeNum)
                
                if decodedInfo.myInfo.myNodeNum != 0
                {
                    print("Save a myInfo")
                    do {
                       print(try decodedInfo.myInfo.jsonString())
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.nodeInfo.num != 0
                {
                    print("Save a nodeInfo")
                    do {
                        print(try decodedInfo.nodeInfo.jsonString())
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.packet.from  != 0
                {
                    print("Save a packet")
                    do {
                        print(try decodedInfo.packet.jsonString())
                    } catch {
                        fatalError("Failed to decode json")
                    }
                }
                
                if decodedInfo.configCompleteID != 0 {
                    print(decodedInfo)
                }
                        
            default:
                print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        
        peripheral.readValue(for: FROMRADIO_characteristic)
    }
}

