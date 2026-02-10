import Foundation

func createDefaultQtRegistry() -> AtomRegistry {
    let registry = AtomRegistry()
    
    // File Type
    registry.register(FtypParser())
    
    // Movie Atoms
    registry.register(MvhdParser())
    registry.register(TkhdParser())
    registry.register(MdhdParser())
    registry.register(HdlrParser())
    registry.register(VmhdParser())
    registry.register(SmhdParser())
    registry.register(DrefParser())
    registry.register(ElstParser())
    
    // Aperture Dimensions
    registry.register(ClefParser())
    registry.register(ProfParser())
    registry.register(EnofParser())
    
    // Sample Table
    registry.register(SttsParser())
    registry.register(StscParser())
    registry.register(StszParser())
    registry.register(StcoParser())
    registry.register(CttsParser())
    registry.register(StssParser())
    registry.register(CslgParser())
    registry.register(SdtpParser())
    registry.register(SbgpParser())
    registry.register(SgpdParser())
    registry.register(StsdParser())
    
    // Custom
    registry.register(CsgmParser())
    
    // Container Atoms
    registry.register(ContainerParser())
    registry.register(MetaParser())
    
    return registry
}
